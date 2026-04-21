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

        // Guardrail: USDA free-text search will ALWAYS return something. For
        // branded/composite dishes (e.g. "BJ's Chocolate Chunk Pizookie") the
        // top hit is often a semantically-unrelated food that shares one token
        // — we saw "Pineapple, frozen, chunks, sweetened" come back for
        // "Chocolate Chunk Pizookie" because of the word "chunks".
        // Reject the match when token coverage is too low OR when no
        // meaningful (non-stopword, length≥4) token matched. The router will
        // then fall through and the meal item ends up without verified
        // nutrition rather than silently wrong.
        let queryTokens = Self.meaningfulTokens(query.itemName)
        let descriptionLower = food.description.lowercased()
        let matched = queryTokens.filter { descriptionLower.contains($0) }
        let coverageRatio: Double = queryTokens.isEmpty ? 1.0
            : Double(matched.count) / Double(queryTokens.count)
        let anyLongTokenMatched = matched.contains(where: { $0.count >= 4 })

        if queryTokens.count >= 2 && (coverageRatio < 0.5 || !anyLongTokenMatched) {
            #if DEBUG
            print("[USDA] REJECT low-confidence match: query=\"\(query.itemName)\" → \"\(food.description)\" coverage=\(matched.count)/\(queryTokens.count) longMatch=\(anyLongTokenMatched)")
            #endif
            return nil
        }

        let nutrition = await service.nutrition(for: food, gramsEstimate: query.gramsEstimate)
        return NutritionMatch(
            sourceId: "usda",
            displayName: food.description,
            externalId: String(food.fdcId),
            nutrition: nutrition,
            confidence: 0.5 + 0.2 * coverageRatio
        )
    }

    // Tokens that actually carry meaning for food matching. Must mirror the
    // stopword/length rules USDAService uses internally so the guardrail and
    // ranker agree on what "coverage" means.
    private static func meaningfulTokens(_ text: String) -> Set<String> {
        let stop: Set<String> = [
            "and", "the", "with", "from", "into", "for", "plus", "some", "any"
        ]
        return Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count > 2 && !stop.contains($0) }
        )
    }
}
