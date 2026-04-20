import Foundation

// A single logged meal as the user sees and saves it. Nutrition numbers here
// come from USDA lookups, never directly from the model.
struct MealEntry: Codable, Sendable, Identifiable {
    let id: UUID
    var capturedAt: Date
    var photoFilename: String?         // relative path in app's Documents
    var mealName: String
    var plateContext: PlateContext
    var referenceObjectPresent: Bool
    var overallConfidence: Double
    var items: [MealItem]
    var totals: NutritionFacts

    init(
        id: UUID = UUID(),
        capturedAt: Date = .now,
        photoFilename: String? = nil,
        mealName: String,
        plateContext: PlateContext,
        referenceObjectPresent: Bool,
        overallConfidence: Double,
        items: [MealItem]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.photoFilename = photoFilename
        self.mealName = mealName
        self.plateContext = plateContext
        self.referenceObjectPresent = referenceObjectPresent
        self.overallConfidence = overallConfidence
        self.items = items
        self.totals = items.map(\.nutrition).reduce(.zero, +)
    }

    mutating func recomputeTotals() {
        totals = items.map(\.nutrition).reduce(.zero, +)
    }
}

struct MealItem: Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var portionAmount: Double
    var portionUnit: PortionUnit
    var gramsEstimate: Double
    var usdaFdcId: Int?
    var usdaDescription: String?
    var nutrition: NutritionFacts
    var itemConfidence: Double
    var preparation: String?
    var brandCue: String?

    init(
        id: UUID = UUID(),
        name: String,
        portionAmount: Double,
        portionUnit: PortionUnit,
        gramsEstimate: Double,
        usdaFdcId: Int?,
        usdaDescription: String?,
        nutrition: NutritionFacts,
        itemConfidence: Double,
        preparation: String? = nil,
        brandCue: String? = nil
    ) {
        self.id = id
        self.name = name
        self.portionAmount = portionAmount
        self.portionUnit = portionUnit
        self.gramsEstimate = gramsEstimate
        self.usdaFdcId = usdaFdcId
        self.usdaDescription = usdaDescription
        self.nutrition = nutrition
        self.itemConfidence = itemConfidence
        self.preparation = preparation
        self.brandCue = brandCue
    }
}
