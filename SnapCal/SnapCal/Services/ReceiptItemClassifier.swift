import Foundation

// Turns a raw OCR'd receipt line into a structured candidate the user
// can review before saving to PantryStore. Local keyword classifier for
// v1 — no model call. Architecture allows swapping in Gemini later when
// we want to handle store-specific abbreviations more gracefully.
enum ReceiptItemClassifier {
    struct Candidate: Identifiable, Equatable {
        let id = UUID()
        var rawLine: String
        var name: String
        var category: PantryCategory
        var quantity: Double
        var unit: PantryUnit
        var suggestedExpiration: Date
        // User flips this off in the confirm sheet to skip the line —
        // useful for taxes, deposits, or junk OCR.
        var include: Bool
    }

    // Substrings — line is dropped if it contains any of these.
    private static let rejectKeywords: Set<String> = [
        "subtotal", "total", "tax", "change", "cash", "credit", "debit",
        "visa", "mastercard", "amex", "tender", "balance", "approved",
        "thank", "you saved", "savings", "discount", "loyalty", "rewards",
        "transaction", "receipt", "store", "register", "cashier", "ref ",
        "ref#", "auth ", "auth#", "phone", "address", "manager",
        "return policy", "exchange", "tip"
    ]

    // Whole-line matches — short receipt boilerplate that would also appear
    // as substrings inside real food names if we used contains() (e.g.
    // "wed" inside "wedge"), so match after trimming punctuation.
    private static let exactRejectWords: Set<String> = [
        "date", "time", "qty", "item", "items", "sku", "special",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "net", "ea", "each", "kg", "lb", "oz", "g", "ml"
    ]

    static func classify(lines: [String], now: Date = .now) -> [Candidate] {
        var out: [Candidate] = []
        for raw in lines {
            guard let candidate = candidate(from: raw, now: now) else { continue }
            out.append(candidate)
        }
        return out
    }

    private static func candidate(from rawLine: String, now: Date) -> Candidate? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty else { return nil }
        for stop in rejectKeywords where lower.contains(stop) { return nil }

        // Per-unit / weight detail rows — the line under each item that
        // says "0.778kg Net @ $5.99/kg". Reject if the line starts with a
        // number followed by a unit, or contains the @ + price-per-unit
        // pattern that only ever appears on detail rows.
        if lower.range(of: #"^\s*\d+(\.\d+)?\s*(kg|g|lb|oz|ml|l)\b"#, options: .regularExpression) != nil {
            return nil
        }
        if lower.contains("@") && lower.range(of: #"\$?\d+\.\d{2}\s*/\s*(kg|g|lb|oz)"#, options: .regularExpression) != nil {
            return nil
        }

        // Strip trailing prices and tax flags ("2.99", "2.99 F", "$2.99 N").
        // The pattern: optional $, digits, optional .digits, optional space + single letter.
        var name = trimmed
        if let priceRange = name.range(of: #"\s*\$?\d+\.\d{2}\s*[A-Z]?\s*$"#, options: .regularExpression) {
            name.removeSubrange(priceRange)
        }
        // Strip leading SKU / UPC-style numeric prefixes.
        if let skuRange = name.range(of: #"^\d{4,}\s+"#, options: .regularExpression) {
            name.removeSubrange(skuRange)
        }
        // Collapse runs of whitespace and stray pipes the OCR sometimes inserts.
        name = name
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Whole-line boilerplate match (DATE, WED, SPECIAL, etc.). Done after
        // price-stripping so "SPECIAL $0.99" → "SPECIAL" → rejected.
        let bareLower = name
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,:;*-_ "))
        if exactRejectWords.contains(bareLower) { return nil }

        // Need at least one alphabetic word ≥ 3 chars to be food, not noise.
        let alphaTokens = name
            .split(whereSeparator: { !$0.isLetter })
            .filter { $0.count >= 3 }
        guard !alphaTokens.isEmpty else { return nil }

        // Drop lines that are mostly digits/punctuation — real product
        // names are predominantly letters even when they include weights
        // or pack counts.
        let letterCount = name.filter { $0.isLetter }.count
        guard Double(letterCount) / Double(max(name.count, 1)) >= 0.5 else { return nil }

        let pretty = prettify(name)
        let category = categoryFor(pretty.lowercased())
        return Candidate(
            rawLine: trimmed,
            name: pretty,
            category: category,
            quantity: 1,
            unit: .count,
            suggestedExpiration: ShelfLife.suggestedExpiration(forName: pretty, category: category, from: now),
            include: true
        )
    }

    private static func categoryFor(_ lowerName: String) -> PantryCategory {
        for (keyword, category) in categoryKeywords {
            if lowerName.contains(keyword) { return category }
        }
        return .other
    }

    // First-match order: more specific keywords first, broader ones later.
    private static let categoryKeywords: [(String, PantryCategory)] = [
        // Frozen first so "frozen pizza" doesn't get caught by "pizza" → other
        ("frozen", .frozen), ("fzn", .frozen), ("ice cream", .frozen),

        // Dairy
        ("milk", .dairy), ("yogurt", .dairy), ("cheese", .dairy),
        ("butter", .dairy), ("cream", .dairy), ("egg", .dairy),

        // Protein
        ("chicken", .protein), ("turkey", .protein), ("pork", .protein),
        ("beef", .protein), ("steak", .protein), ("bacon", .protein),
        ("sausage", .protein), ("ham", .protein), ("salmon", .protein),
        ("tuna", .protein), ("shrimp", .protein), ("fish", .protein),
        ("tofu", .protein), ("tempeh", .protein),

        // Produce
        ("apple", .produce), ("banana", .produce), ("berr", .produce),
        ("grape", .produce), ("orange", .produce), ("lemon", .produce),
        ("lime", .produce), ("avocado", .produce), ("tomato", .produce),
        ("onion", .produce), ("garlic", .produce), ("pepper", .produce),
        ("lettuce", .produce), ("spinach", .produce), ("kale", .produce),
        ("broccoli", .produce), ("carrot", .produce), ("cucumber", .produce),
        ("potato", .produce), ("mushroom", .produce), ("herbs", .produce),
        ("salad", .produce),

        // Grains / bakery
        ("bread", .grains), ("bagel", .grains), ("muffin", .grains),
        ("tortilla", .grains), ("pasta", .grains), ("rice", .grains),
        ("oats", .grains), ("cereal", .grains), ("granola", .grains),

        // Snacks
        ("chip", .snack), ("crisp", .snack), ("cookie", .snack),
        ("candy", .snack), ("bar", .snack), ("popcorn", .snack),
        ("cracker", .snack), ("nut", .snack),

        // Drinks
        ("juice", .drink), ("soda", .drink), ("coffee", .drink),
        ("tea", .drink), ("water", .drink), ("seltzer", .drink),
        ("beer", .drink), ("wine", .drink),

        // Pantry catch-all (after specific items so "pasta sauce" hits sauce → pantry)
        ("sauce", .pantry), ("oil", .pantry), ("vinegar", .pantry),
        ("salsa", .pantry), ("hummus", .pantry), ("soup", .pantry),
        ("can ", .pantry), ("canned", .pantry), ("flour", .pantry),
        ("sugar", .pantry), ("salt", .pantry), ("honey", .pantry),
        ("syrup", .pantry)
    ]

    // ALL-CAPS receipt strings → Title Case so the pantry list looks
    // human. Skip short tokens and punctuation.
    private static func prettify(_ raw: String) -> String {
        let words = raw.split(separator: " ").map { word -> String in
            let s = String(word)
            if s.allSatisfy({ $0.isUppercase || !$0.isLetter }) {
                return s.capitalized
            }
            return s
        }
        return words.joined(separator: " ")
    }
}
