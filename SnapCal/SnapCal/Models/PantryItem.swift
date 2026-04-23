import Foundation

// A single ingredient/food item the user has on hand. Feeds Cook's
// recipe suggestions later (filter to recipes we can make with what's
// stocked) and the shopping list when we ship that.
struct PantryItem: Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var quantity: Double
    var unit: PantryUnit
    var category: PantryCategory
    var expirationDate: Date?
    var note: String?
    var addedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double = 1,
        unit: PantryUnit = .count,
        category: PantryCategory = .other,
        expirationDate: Date? = nil,
        note: String? = nil,
        addedAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.expirationDate = expirationDate
        self.note = note
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }

    var expirationStatus: ExpirationStatus {
        guard let expiration = expirationDate else { return .none }
        let days = Calendar.current.dateComponents([.day], from: .now, to: expiration).day ?? 0
        if days < 0 { return .expired }
        if days <= 3 { return .soon(days: days) }
        return .ok(days: days)
    }
}

enum PantryUnit: String, Codable, Sendable, CaseIterable, Identifiable {
    case count, oz, lb, g, kg, mL, L, cup, tbsp, tsp

    var id: String { rawValue }
    var label: String {
        switch self {
        case .count: return "ct"
        case .oz:    return "oz"
        case .lb:    return "lb"
        case .g:     return "g"
        case .kg:    return "kg"
        case .mL:    return "mL"
        case .L:     return "L"
        case .cup:   return "cup"
        case .tbsp:  return "tbsp"
        case .tsp:   return "tsp"
        }
    }
}

enum PantryCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case produce, protein, dairy, grains, frozen, pantry, snack, drink, other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .produce: return "Produce"
        case .protein: return "Protein"
        case .dairy:   return "Dairy"
        case .grains:  return "Grains"
        case .frozen:  return "Frozen"
        case .pantry:  return "Pantry"
        case .snack:   return "Snacks"
        case .drink:   return "Drinks"
        case .other:   return "Other"
        }
    }
    var systemImage: String {
        switch self {
        case .produce: return "carrot.fill"
        case .protein: return "fish.fill"
        case .dairy:   return "drop.fill"
        case .grains:  return "basket.fill"
        case .frozen:  return "snowflake"
        case .pantry:  return "cabinet.fill"
        case .snack:   return "popcorn.fill"
        case .drink:   return "cup.and.saucer.fill"
        case .other:   return "square.grid.2x2.fill"
        }
    }
}

enum ExpirationStatus: Sendable, Equatable {
    case none
    case ok(days: Int)
    case soon(days: Int)
    case expired
}
