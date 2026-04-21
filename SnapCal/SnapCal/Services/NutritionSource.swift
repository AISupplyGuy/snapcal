import Foundation

// A pluggable backend for per-item nutrition lookup.
// USDA, chain menu databases, Open Food Facts, etc. all conform to this.
protocol NutritionSource: Sendable {
    var id: String { get }
    func lookup(query: NutritionQuery) async throws -> NutritionMatch?
}

struct NutritionQuery: Sendable {
    let itemName: String
    let brandCue: String?
    let gramsEstimate: Double
    let plateContext: PlateContext
}

struct NutritionMatch: Sendable {
    let sourceId: String       // "usda", "chipotle", "openfoodfacts"
    let displayName: String    // human-readable, shown on the meal card
    let externalId: String?    // FDC id, menu item UUID, UPC, etc.
    let nutrition: NutritionFacts
    let confidence: Double     // 0–1
    let sizeOptions: [ChainSizeOption]?
    let selectedSizeKey: String?
}
