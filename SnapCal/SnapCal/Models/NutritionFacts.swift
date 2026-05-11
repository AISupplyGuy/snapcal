import Foundation

struct NutritionFacts: Codable, Sendable, Equatable, Hashable {
    var calories: Double
    var proteinGrams: Double
    var carbGrams: Double
    var fatGrams: Double
    var fiberGrams: Double

    static let zero = NutritionFacts(calories: 0, proteinGrams: 0, carbGrams: 0, fatGrams: 0, fiberGrams: 0)

    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            calories: lhs.calories + rhs.calories,
            proteinGrams: lhs.proteinGrams + rhs.proteinGrams,
            carbGrams: lhs.carbGrams + rhs.carbGrams,
            fatGrams: lhs.fatGrams + rhs.fatGrams,
            fiberGrams: lhs.fiberGrams + rhs.fiberGrams
        )
    }

    func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories * factor,
            proteinGrams: proteinGrams * factor,
            carbGrams: carbGrams * factor,
            fatGrams: fatGrams * factor,
            fiberGrams: fiberGrams * factor
        )
    }
}
