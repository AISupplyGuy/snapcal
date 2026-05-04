import Foundation

// Cleans up the raw receipt-line descriptions Veryfi gives us by asking
// Gemini to expand abbreviations ("GG OATMILK" → "Good & Gather Oat
// Milk"), assign a pantry category, and drop anything that isn't food.
// Runs once per receipt with all the lines in a single prompt — that's
// one network round-trip, ~1-2 seconds, ~half a cent on Flash.
//
// The output preserves the original quantity / unit / total fields the
// upstream candidate already had; we only overwrite name + category +
// suggestedExpiration (recomputed against the expanded name so ShelfLife
// keyword matches actually fire).
enum GeminiReceiptNormalizer {
    enum NormalizerError: Error, LocalizedError {
        case missingAPIKey
        case http(Int, String)
        case parse(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:        return "GEMINI_API_KEY is not set."
            case .http(let s, let b):   return "Gemini HTTP \(s): \(b.prefix(200))"
            case .parse(let d):         return "Gemini parse failed: \(d)"
            }
        }
    }

    static func normalize(
        candidates: [ReceiptItemClassifier.Candidate],
        now: Date = .now
    ) async throws -> [ReceiptItemClassifier.Candidate] {
        guard !candidates.isEmpty else { return candidates }
        guard let key = GeminiService.resolve("GEMINI_API_KEY"), !key.isEmpty else {
            throw NormalizerError.missingAPIKey
        }
        // Pinned: receipts use 2.5-flash regardless of the GEMINI_MODEL
        // env var, which configures the meal-analysis pipeline only.
        let model = "gemini-2.5-flash"

        let inputs = candidates.enumerated().map { idx, c in
            ["index": idx, "raw": c.rawLine, "name": c.name] as [String: Any]
        }
        let inputJSON = String(
            data: try JSONSerialization.data(withJSONObject: inputs),
            encoding: .utf8
        ) ?? "[]"

        let prompt = """
        You are normalizing line items from a US grocery receipt.

        For EACH input item return one object with:
        - index: integer matching the input index
        - is_food: true if the line represents an edible product (groceries, beverages, snacks, prepared food). Set false for non-food items (paper towels, diapers, soap, batteries, gift cards, services).
        - name: the expanded product name in Title Case. Resolve common store-brand abbreviations:
            • "GG" or "G&G" → "Good & Gather"
            • "MV" or "MARKET VALUE" → "Market Pantry"
            • "FB" → "Favorite Day"
            • "GV" → "Great Value"
            • "KS" → "Kirkland Signature"
            • "TJ" or "TJ'S" → "Trader Joe's"
            • "WF" → "Whole Foods 365"
          Strip noise like trailing size codes ("8.80Z" → "8.8 oz" appended to name), SKU prefixes, and tax flags ("BF", "TF").
          Be specific: "STARBUCKS" on a grocery section likely means "Starbucks Coffee K-Cups" or "Starbucks Ground Coffee" — pick the most likely product.
        - category: exactly one of: produce, protein, dairy, grains, frozen, pantry, snack, drink, other.
            • produce: fresh fruit/vegetables
            • protein: meat, poultry, seafood, tofu, plant-based meat, eggs (eggs go in dairy if uncertain)
            • dairy: milk, cheese, yogurt, butter, cream, eggs, plant-based milks
            • grains: bread, pasta, rice, cereal, oats, tortillas
            • frozen: anything frozen
            • pantry: shelf-stable cans, jars, sauces, oils, spices, condiments, pickles, dry goods
            • snack: chips, cookies, crackers, candy, granola bars
            • drink: beverages, coffee, tea, soda, juice, water
            • other: only if truly nothing else fits

        Input (JSON array):
        \(inputJSON)

        Output: a JSON object {"items": [...]} where items is an array of the objects above, one per input. Do not skip items — set is_food=false for non-food but include them.
        """

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")!
        let body: [String: Any] = [
            "contents": [[
                "parts": [["text": prompt]]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.1
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NormalizerError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let envelope = try JSONDecoder().decode(GeminiTextEnvelope.self, from: data)
        guard let text = envelope.candidates.first?.content.parts.first?.text,
              let textData = text.data(using: .utf8)
        else {
            throw NormalizerError.parse("empty response")
        }

        let result: NormalizedResult
        do {
            result = try JSONDecoder().decode(NormalizedResult.self, from: textData)
        } catch {
            throw NormalizerError.parse("decode failed: \(error) — raw: \(text.prefix(300))")
        }

        // Index normalized items by their `index` field so we can apply
        // them positionally even if Gemini reorders or drops some.
        let byIndex = Dictionary(uniqueKeysWithValues: result.items.map { ($0.index, $0) })

        var output: [ReceiptItemClassifier.Candidate] = []
        for (i, original) in candidates.enumerated() {
            guard let n = byIndex[i] else {
                output.append(original)
                continue
            }
            // Drop non-food lines entirely — pantry should not contain
            // paper towels, gift cards, etc.
            guard n.is_food else { continue }

            let category = mapCategory(n.category) ?? original.category
            let prettyName = n.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var updated = original
            updated.name = prettyName.isEmpty ? original.name : prettyName
            updated.category = category
            updated.suggestedExpiration = ShelfLife.suggestedExpiration(
                forName: updated.name,
                category: category,
                from: now
            )
            output.append(updated)
        }
        return output
    }

    private static func mapCategory(_ raw: String) -> PantryCategory? {
        switch raw.lowercased() {
        case "produce":  return .produce
        case "protein":  return .protein
        case "dairy":    return .dairy
        case "grains":   return .grains
        case "frozen":   return .frozen
        case "pantry":   return .pantry
        case "snack":    return .snack
        case "drink":    return .drink
        case "other":    return .other
        default:         return nil
        }
    }
}

// MARK: - Decoding shapes

private struct GeminiTextEnvelope: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}

private struct NormalizedResult: Decodable {
    struct Item: Decodable {
        let index: Int
        let is_food: Bool
        let name: String
        let category: String
    }
    let items: [Item]
}
