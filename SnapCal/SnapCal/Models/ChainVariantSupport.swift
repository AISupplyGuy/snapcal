import Foundation

struct ChainSizeOption: Codable, Sendable, Hashable {
    let key: String
    let label: String
}

enum ChainVariantSupport {
    static func adjustedQueryName(for item: MealItem, targetSizeKey: String) -> String {
        var stripped = item.name
        for alias in sizeTerms {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: alias) + "\\b"
            stripped = stripped.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        stripped = stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if targetSizeKey == "regular" {
            return stripped
        }
        return "\(targetSizeKey) \(stripped)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func preferenceKey(for item: MealItem) -> String? {
        guard let slug = item.matchedSourceId else { return nil }
        let signature = familySignature(for: item.name)
        guard !signature.isEmpty else { return nil }
        return "sizeVariant.\(slug).\(signature)"
    }

    private static func familySignature(for name: String) -> String {
        let tokens = name
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { !sizeTerms.contains($0) && $0 != "gluten" && $0 != "free" && $0 != "gf" }
        return tokens.joined(separator: "_")
    }

    private static let sizeTerms: Set<String> = [
        "kids", "mini", "small", "medium", "large", "regular",
        "tall", "grande", "venti", "trenta"
    ]
}
