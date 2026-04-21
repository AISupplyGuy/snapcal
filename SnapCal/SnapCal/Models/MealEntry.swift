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

enum DietaryVariantPreference: String, Codable, Sendable {
    case unknown
    case glutenFree
    case notGlutenFree
}

struct MealItem: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var portionAmount: Double
    var portionUnit: PortionUnit
    var gramsEstimate: Double
    var usdaFdcId: Int?
    var usdaDescription: String?      // display name from the matched source (USDA desc, chain name, etc.)
    var matchedSourceId: String?      // "usda", "chipotle", "openfoodfacts", nil if no match
    var matchConfidence: Double?      // 0–1 from the NutritionSource
    var nutrition: NutritionFacts
    // Per-100g baseline snapshot from the source at analysis time. The slider
    // rescales `nutrition` live from this — so the kcal label tracks the thumb
    // and we never round-trip through a lossy divide-then-multiply.
    var baselinePer100g: NutritionFacts
    var itemConfidence: Double
    var preparation: String?
    var brandCue: String?
    var dietaryVariantPreference: DietaryVariantPreference?

    init(
        id: UUID = UUID(),
        name: String,
        portionAmount: Double,
        portionUnit: PortionUnit,
        gramsEstimate: Double,
        usdaFdcId: Int?,
        usdaDescription: String?,
        matchedSourceId: String? = nil,
        matchConfidence: Double? = nil,
        nutrition: NutritionFacts,
        baselinePer100g: NutritionFacts,
        itemConfidence: Double,
        preparation: String? = nil,
        brandCue: String? = nil,
        dietaryVariantPreference: DietaryVariantPreference? = nil
    ) {
        self.id = id
        self.name = name
        self.portionAmount = portionAmount
        self.portionUnit = portionUnit
        self.gramsEstimate = gramsEstimate
        self.usdaFdcId = usdaFdcId
        self.usdaDescription = usdaDescription
        self.matchedSourceId = matchedSourceId
        self.matchConfidence = matchConfidence
        self.nutrition = nutrition
        self.baselinePer100g = baselinePer100g
        self.itemConfidence = itemConfidence
        self.preparation = preparation
        self.brandCue = brandCue
        self.dietaryVariantPreference = dietaryVariantPreference
    }
}
