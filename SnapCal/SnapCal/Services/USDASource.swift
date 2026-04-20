import Foundation

actor USDASource: NutritionSource {
    let id = "usda"
    private let service: USDAService

    init(service: USDAService) {
        self.service = service
    }

    func lookup(query: NutritionQuery) async throws -> NutritionMatch? {
        let food: USDAFood
        do {
            food = try await service.bestMatch(for: query.itemName)
        } catch USDAError.noMatch {
            return nil
        }
        let nutrition = await service.nutrition(for: food, gramsEstimate: query.gramsEstimate)
        return NutritionMatch(
            sourceId: "usda",
            displayName: food.description,
            externalId: String(food.fdcId),
            nutrition: nutrition,
            confidence: 0.7
        )
    }
}
