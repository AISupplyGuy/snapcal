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
    // Which Gemini tier produced these numbers ("flash", "pro", or
    // "flash+pro" when both ran for divergence comparison). Used by
    // analytics / debug and surfaced on the card when verification is asked.
    var modelTier: String
    // Set when Flash and Pro produced materially different totals on a
    // low-confidence photo — the UI should ask the user to sanity-check
    // before saving.
    var needsVerification: Bool

    init(
        id: UUID = UUID(),
        capturedAt: Date = .now,
        photoFilename: String? = nil,
        mealName: String,
        plateContext: PlateContext,
        referenceObjectPresent: Bool,
        overallConfidence: Double,
        items: [MealItem],
        modelTier: String = "flash",
        needsVerification: Bool = false
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
        self.modelTier = modelTier
        self.needsVerification = needsVerification
    }

    mutating func recomputeTotals() {
        totals = items.map(\.nutrition).reduce(.zero, +)
    }

    // Custom Codable to keep old saved meals decodable after the two new
    // fields were added. Missing fields default to "flash" / false.
    enum CodingKeys: String, CodingKey {
        case id, capturedAt, photoFilename, mealName, plateContext
        case referenceObjectPresent, overallConfidence, items, totals
        case modelTier, needsVerification
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        self.photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
        self.mealName = try c.decode(String.self, forKey: .mealName)
        self.plateContext = try c.decode(PlateContext.self, forKey: .plateContext)
        self.referenceObjectPresent = try c.decode(Bool.self, forKey: .referenceObjectPresent)
        self.overallConfidence = try c.decode(Double.self, forKey: .overallConfidence)
        self.items = try c.decode([MealItem].self, forKey: .items)
        self.totals = try c.decode(NutritionFacts.self, forKey: .totals)
        self.modelTier = try c.decodeIfPresent(String.self, forKey: .modelTier) ?? "flash"
        self.needsVerification = try c.decodeIfPresent(Bool.self, forKey: .needsVerification) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(capturedAt, forKey: .capturedAt)
        try c.encodeIfPresent(photoFilename, forKey: .photoFilename)
        try c.encode(mealName, forKey: .mealName)
        try c.encode(plateContext, forKey: .plateContext)
        try c.encode(referenceObjectPresent, forKey: .referenceObjectPresent)
        try c.encode(overallConfidence, forKey: .overallConfidence)
        try c.encode(items, forKey: .items)
        try c.encode(totals, forKey: .totals)
        try c.encode(modelTier, forKey: .modelTier)
        try c.encode(needsVerification, forKey: .needsVerification)
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
    var availableSizeOptions: [ChainSizeOption]?
    var selectedSizeKey: String?

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
        dietaryVariantPreference: DietaryVariantPreference? = nil,
        availableSizeOptions: [ChainSizeOption]? = nil,
        selectedSizeKey: String? = nil
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
        self.availableSizeOptions = availableSizeOptions
        self.selectedSizeKey = selectedSizeKey
    }
}
