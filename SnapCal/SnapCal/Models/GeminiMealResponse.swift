import Foundation

struct GeminiMealResponse: Codable, Sendable {
    let mealName: String
    let items: [IdentifiedItem]
    let plateContext: PlateContext
    let referenceObjectPresent: Bool
    let overallConfidence: Double
    let clarifyingQuestions: [String]

    enum CodingKeys: String, CodingKey {
        case mealName = "meal_name"
        case items
        case plateContext = "plate_context"
        case referenceObjectPresent = "reference_object_present"
        case overallConfidence = "overall_confidence"
        case clarifyingQuestions = "clarifying_questions"
    }
}

struct IdentifiedItem: Codable, Sendable, Identifiable {
    var id = UUID()
    let name: String
    let portionAmount: Double
    let portionUnit: PortionUnit
    let portionDescription: String
    let preparation: String?
    let brandCue: String?
    let itemConfidence: Double

    enum CodingKeys: String, CodingKey {
        case name
        case portionAmount = "portion_amount"
        case portionUnit = "portion_unit"
        case portionDescription = "portion_description"
        case preparation
        case brandCue = "brand_cue"
        case itemConfidence = "item_confidence"
    }
}

enum PortionUnit: String, Codable, Sendable {
    case grams = "g"
    case ounces = "oz"
    case cup
    case slice
    case piece
    case tablespoon = "tbsp"
    case teaspoon = "tsp"
    case milliliters = "ml"

    var gramsPerUnit: Double? {
        switch self {
        case .grams: return 1.0
        case .ounces: return 28.3495
        case .tablespoon: return 14.0
        case .teaspoon: return 4.67
        case .milliliters: return 1.0
        case .cup, .slice, .piece: return nil
        }
    }
}

enum PlateContext: String, Codable, Sendable {
    case home
    case restaurant
    case takeout
    case packaged
    case unknown
}
