import Foundation

// Static expiration windows for grocery items, derived from USDA / FSIS
// food-safety guidelines. The architecture rule: never ask the model
// "how long does chicken last" — bake the answer into a table the
// product can update independently.
//
// `ShelfLife.suggestedDays(for:)` is the single entry point. It
// prefers a keyword-specific window (e.g. "berries" → 4d) and falls
// back to a category default (e.g. produce → 7d) when nothing matches.
enum ShelfLife {
    static func suggestedDays(forName name: String, category: PantryCategory) -> Int {
        let lower = name.lowercased()
        for (keyword, days) in keywordWindows {
            if lower.contains(keyword) { return days }
        }
        return categoryDefault(for: category)
    }

    static func suggestedExpiration(forName name: String, category: PantryCategory, from base: Date = .now) -> Date {
        let days = suggestedDays(forName: name, category: category)
        return Calendar.current.date(byAdding: .day, value: days, to: base) ?? base
    }

    // Keyword windows are checked first. Order roughly by specificity so
    // "ground beef" hits before "beef" — first match wins.
    private static let keywordWindows: [(String, Int)] = [
        // Produce — short-lived
        ("berries", 4), ("strawberr", 4), ("raspberr", 4), ("blueberr", 5),
        ("spinach", 5), ("arugula", 5), ("kale", 7), ("lettuce", 6),
        ("herbs", 5), ("basil", 5), ("cilantro", 5), ("parsley", 7),
        ("avocado", 4), ("tomato", 7), ("cucumber", 7), ("pepper", 8),
        ("mushroom", 5), ("asparagus", 4), ("broccoli", 7),

        // Produce — longer
        ("apple", 21), ("orange", 14), ("lemon", 21), ("lime", 14),
        ("banana", 5), ("grape", 7), ("melon", 7),
        ("onion", 30), ("garlic", 30), ("potato", 21), ("carrot", 21),

        // Dairy
        ("milk", 7), ("cream", 7), ("half and half", 7),
        ("yogurt", 14), ("butter", 30), ("cheese", 21),
        ("egg", 21),

        // Protein — raw
        ("ground beef", 2), ("ground turkey", 2), ("ground chicken", 2),
        ("chicken", 2), ("turkey", 3), ("pork", 4), ("beef", 4),
        ("salmon", 2), ("tuna", 2), ("fish", 2), ("shrimp", 2),
        ("bacon", 7), ("sausage", 4), ("hot dog", 7), ("deli", 5),
        ("tofu", 7), ("tempeh", 14),

        // Bread & bakery
        ("bread", 5), ("bagel", 5), ("muffin", 4), ("croissant", 3),
        ("tortilla", 14),

        // Pantry / dry / canned
        ("rice", 365), ("pasta", 365), ("flour", 365), ("sugar", 365),
        ("oats", 180), ("cereal", 180), ("cracker", 90),
        ("can ", 365), ("canned", 365),
        ("soup", 30), ("sauce", 30), ("salsa", 14), ("hummus", 7),
        ("oil", 365), ("vinegar", 365), ("honey", 365), ("syrup", 365),

        // Frozen
        ("frozen", 90), ("fzn", 90), ("ice cream", 60),

        // Snacks & drinks
        ("chip", 60), ("cookie", 30), ("candy", 90), ("bar", 90),
        ("juice", 7), ("soda", 90), ("coffee", 30), ("tea", 365),
        ("water", 180), ("seltzer", 90)
    ]

    private static func categoryDefault(for category: PantryCategory) -> Int {
        switch category {
        case .produce: return 7
        case .protein: return 3
        case .dairy:   return 10
        case .grains:  return 90
        case .frozen:  return 90
        case .pantry:  return 365
        case .snack:   return 60
        case .drink:   return 60
        case .other:   return 14
        }
    }
}
