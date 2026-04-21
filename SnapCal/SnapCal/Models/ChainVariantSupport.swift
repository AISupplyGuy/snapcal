import Foundation

struct ChainSizeOption: Sendable, Hashable {
    let key: String
    let label: String
}

enum ChainVariantSupport {
    private struct SizeConfig {
        let options: [ChainSizeOption]
        let aliasesByKey: [String: [String]]
        let familyKeywords: [String]
    }

    private static let configs: [String: SizeConfig] = [
        "bjs": SizeConfig(
            options: [
                ChainSizeOption(key: "regular", label: "Regular"),
                ChainSizeOption(key: "mini", label: "Mini")
            ],
            aliasesByKey: [
                "regular": ["regular"],
                "mini": ["mini"]
            ],
            familyKeywords: ["pizookie"]
        ),
        "mcdonalds": SizeConfig(
            options: [
                ChainSizeOption(key: "small", label: "Small"),
                ChainSizeOption(key: "medium", label: "Medium"),
                ChainSizeOption(key: "large", label: "Large")
            ],
            aliasesByKey: [
                "small": ["small"],
                "medium": ["medium", "regular"],
                "large": ["large"]
            ],
            familyKeywords: ["fries", "coke", "sprite", "fanta", "drink", "shake", "soda", "tea", "coffee"]
        )
    ]

    static func sizeOptions(for item: MealItem) -> [ChainSizeOption] {
        guard let slug = item.matchedSourceId, let cfg = configs[slug] else { return [] }
        let text = "\(item.name) \(item.usdaDescription ?? "")".lowercased()
        let applies = cfg.familyKeywords.contains { text.contains($0) }
            || hasAnySizeAlias(in: text, config: cfg)
        return applies ? cfg.options : []
    }

    static func selectedSizeKey(for item: MealItem) -> String? {
        guard let slug = item.matchedSourceId, let cfg = configs[slug] else { return nil }
        let text = "\(item.name) \(item.usdaDescription ?? "")".lowercased()
        for option in cfg.options {
            let aliases = cfg.aliasesByKey[option.key] ?? []
            if aliases.contains(where: { text.contains($0) }) {
                return option.key
            }
        }
        return nil
    }

    static func adjustedQueryName(for item: MealItem, targetSizeKey: String) -> String {
        guard let slug = item.matchedSourceId, let cfg = configs[slug] else { return item.name }

        var stripped = item.name
        let allAliases = Set(cfg.aliasesByKey.values.flatMap { $0 })
        for alias in allAliases {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: alias) + "\\b"
            stripped = stripped.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        stripped = stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let primaryAlias = cfg.aliasesByKey[targetSizeKey]?.first
        if targetSizeKey == "regular" && slug == "bjs" {
            return stripped
        }
        guard let alias = primaryAlias else { return stripped }
        return "\(alias) \(stripped)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func preferenceKey(for item: MealItem) -> String? {
        guard let slug = item.matchedSourceId else { return nil }
        if slug == "bjs" {
            let text = "\(item.name) \(item.usdaDescription ?? "")".lowercased()
            if text.contains("pizookie") { return "sizeVariant.bjs.pizookie" }
        }
        if slug == "mcdonalds" {
            let text = "\(item.name) \(item.usdaDescription ?? "")".lowercased()
            if text.contains("fries") { return "sizeVariant.mcdonalds.fries" }
            if text.contains("drink") || text.contains("coke") || text.contains("sprite") || text.contains("fanta") {
                return "sizeVariant.mcdonalds.drinks"
            }
        }
        return nil
    }

    private static func hasAnySizeAlias(in text: String, config: SizeConfig) -> Bool {
        for aliases in config.aliasesByKey.values where aliases.contains(where: text.contains) {
            return true
        }
        return false
    }
}
