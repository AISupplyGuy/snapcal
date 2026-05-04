import Foundation
import UIKit

// Calls Veryfi's documents endpoint with a receipt image and maps the
// returned line items into ReceiptItemClassifier.Candidate so the rest
// of the receipt flow (review sheet, save → PantryStore) is unchanged.
//
// Veryfi gives us much better names, categories, and noise filtering
// than our local heuristics — totals/discounts/dates never appear as
// line items. We still pass the result through ShelfLife for expiration
// dates since Veryfi doesn't predict expiry.
enum VeryfiReceiptService {
    enum ServiceError: Error, LocalizedError {
        case notConfigured
        case encodingFailed
        case http(Int, String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured:    return "Veryfi credentials are missing."
            case .encodingFailed:   return "Couldn't prepare the receipt image."
            case .http(let code, let body):
                return "Veryfi returned HTTP \(code): \(body.prefix(160))"
            case .decodingFailed:   return "Veryfi returned an unexpected response shape."
            }
        }
    }

    private static let endpoint = URL(string: "https://api.veryfi.com/api/v8/partner/documents/")!

    static func parseReceipt(image: UIImage, now: Date = .now) async throws -> [ReceiptItemClassifier.Candidate] {
        guard VeryfiConfig.isConfigured else { throw ServiceError.notConfigured }
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { throw ServiceError.encodingFailed }

        let body: [String: Any] = [
            "file_name": "receipt.jpg",
            "file_data": jpeg.base64EncodedString(),
            // Don't store the receipt on Veryfi's servers after parsing —
            // they delete it immediately. We keep nothing remote.
            "auto_delete": 1,
            "boost_mode": 1
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(VeryfiConfig.clientId, forHTTPHeaderField: "Client-Id")
        request.setValue("apikey \(VeryfiConfig.username):\(VeryfiConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        request.httpBody = payload

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.http(http.statusCode, bodyText)
        }

        // Dump the raw JSON so we can inspect what Veryfi actually returned
        // for this receipt — descriptions, normalized names, categories,
        // and any fields we're not yet mapping. Remove once the mapping is
        // tuned for the receipt shapes we care about.
        if let json = String(data: data, encoding: .utf8) {
            print("[Veryfi] raw response (\(data.count) bytes):\n\(json)")
        }

        let decoded = try JSONDecoder().decode(VeryfiDocument.self, from: data)
        print("[Veryfi] parsed \(decoded.line_items.count) line items")
        for (i, item) in decoded.line_items.enumerated() {
            print("[Veryfi]   #\(i): description=\(item.description ?? "nil"), normalized=\(item.normalized_description ?? "nil"), category=\(item.category ?? "nil"), qty=\(item.quantity?.description ?? "nil") \(item.unit_of_measure ?? "")")
        }
        return decoded.line_items.compactMap { Self.candidate(from: $0, now: now) }
    }

    // MARK: - Mapping

    private static func candidate(from item: VeryfiLineItem, now: Date) -> ReceiptItemClassifier.Candidate? {
        // Prefer the normalized description Veryfi assigns, fall back to
        // the verbatim line. Skip lines without any usable name.
        let rawName = (item.normalized_description ?? item.description ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else { return nil }

        // Veryfi sometimes returns negative line items for coupons /
        // discounts. We don't want those in the pantry.
        if let total = item.total, total < 0 { return nil }

        let category = mapCategory(item.category, name: rawName.lowercased())
        let (qty, unit) = mapQuantity(item)

        return ReceiptItemClassifier.Candidate(
            rawLine: item.description ?? rawName,
            name: rawName.capitalized,
            category: category,
            quantity: qty,
            unit: unit,
            suggestedExpiration: ShelfLife.suggestedExpiration(forName: rawName, category: category, from: now),
            include: true
        )
    }

    private static func mapCategory(_ veryfi: String?, name: String) -> PantryCategory {
        // Veryfi's category vocabulary is broader than ours — these are
        // the strings we've actually seen in their docs/responses for
        // grocery receipts. Anything unknown falls through to a name-
        // based keyword check, then to .other.
        switch (veryfi ?? "").lowercased() {
        case let s where s.contains("produce") || s.contains("fruit") || s.contains("vegetable"):
            return .produce
        case let s where s.contains("meat") || s.contains("seafood") || s.contains("poultry"):
            return .protein
        case let s where s.contains("dairy") || s.contains("egg"):
            return .dairy
        case let s where s.contains("frozen"):
            return .frozen
        case let s where s.contains("bakery") || s.contains("bread") || s.contains("grain"):
            return .grains
        case let s where s.contains("snack"):
            return .snack
        case let s where s.contains("beverage") || s.contains("drink"):
            return .drink
        case let s where s.contains("pantry") || s.contains("can") || s.contains("dry"):
            return .pantry
        default:
            return categoryFromName(name)
        }
    }

    // Mirrors the keyword fallback the local classifier uses. Kept here
    // so we don't depend on the local classifier's private state.
    private static func categoryFromName(_ lower: String) -> PantryCategory {
        let pairs: [(String, PantryCategory)] = [
            ("frozen", .frozen), ("ice cream", .frozen),
            ("milk", .dairy), ("yogurt", .dairy), ("cheese", .dairy), ("egg", .dairy), ("butter", .dairy), ("cream", .dairy),
            ("chicken", .protein), ("beef", .protein), ("pork", .protein), ("turkey", .protein),
            ("bacon", .protein), ("salmon", .protein), ("tuna", .protein), ("shrimp", .protein),
            ("apple", .produce), ("banana", .produce), ("berr", .produce), ("grape", .produce),
            ("orange", .produce), ("lemon", .produce), ("lime", .produce), ("avocado", .produce),
            ("tomato", .produce), ("onion", .produce), ("pepper", .produce), ("lettuce", .produce),
            ("spinach", .produce), ("kale", .produce), ("broccoli", .produce), ("carrot", .produce),
            ("cucumber", .produce), ("potato", .produce), ("mushroom", .produce), ("zucchini", .produce),
            ("bread", .grains), ("bagel", .grains), ("pasta", .grains), ("rice", .grains), ("oats", .grains),
            ("chip", .snack), ("cookie", .snack), ("candy", .snack), ("cracker", .snack),
            ("juice", .drink), ("soda", .drink), ("coffee", .drink), ("tea", .drink), ("water", .drink)
        ]
        for (k, c) in pairs where lower.contains(k) { return c }
        return .other
    }

    private static func mapQuantity(_ item: VeryfiLineItem) -> (Double, PantryUnit) {
        let qty = item.quantity ?? 1.0
        switch (item.unit_of_measure ?? "").lowercased() {
        case "kg", "kilogram", "kilograms": return (qty, .kg)
        case "g", "gram", "grams":          return (qty, .g)
        case "lb", "lbs", "pound", "pounds":return (qty, .lb)
        case "oz", "ounce", "ounces":       return (qty, .oz)
        case "ml", "milliliter":            return (qty, .mL)
        case "l", "liter", "liters":        return (qty, .L)
        default:                            return (max(qty, 1), .count)
        }
    }
}

// MARK: - Decoding shapes (only the fields we actually consume)

private struct VeryfiDocument: Decodable {
    let line_items: [VeryfiLineItem]
}

private struct VeryfiLineItem: Decodable {
    let description: String?
    let normalized_description: String?
    let category: String?
    let quantity: Double?
    let unit_of_measure: String?
    let total: Double?
}
