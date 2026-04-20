import Foundation

// Orchestrates: photo → Gemini identification → NutritionRouter per item → MealEntry with computed totals.
// The model never supplies calorie numbers. The router is the only path that writes nutrition.
actor MealAnalysisPipeline {
    private let gemini: GeminiService
    private let router: NutritionRouter

    init(gemini: GeminiService, router: NutritionRouter) {
        self.gemini = gemini
        self.router = router
    }

    func analyze(imageJPEG: Data) async throws -> MealEntry {
        let identification = try await gemini.identifyMeal(imageJPEG: imageJPEG)

        // Per-item lookups run in parallel. The router handles source priority.
        let router = self.router
        let indexedItems: [(Int, MealItem)] = await withTaskGroup(of: (Int, MealItem).self) { group in
            for (index, identified) in identification.items.enumerated() {
                let grams = self.normalizedGrams(for: identified)
                let query = NutritionQuery(
                    itemName: identified.name,
                    brandCue: identified.brandCue,
                    gramsEstimate: grams,
                    plateContext: identification.plateContext
                )
                group.addTask {
                    let match = await router.lookup(query: query)
                    // Populate both the legacy usda fields (so existing display code works)
                    // and the new matchedSourceId field (so new display code can differentiate).
                    let item = MealItem(
                        name: identified.name,
                        portionAmount: identified.portionAmount,
                        portionUnit: identified.portionUnit,
                        gramsEstimate: grams,
                        usdaFdcId: {
                            guard match?.sourceId == "usda",
                                  let ext = match?.externalId, let id = Int(ext) else { return nil }
                            return id
                        }(),
                        usdaDescription: match?.displayName,
                        matchedSourceId: match?.sourceId,
                        matchConfidence: match?.confidence,
                        nutrition: match?.nutrition ?? .zero,
                        itemConfidence: identified.itemConfidence,
                        preparation: identified.preparation,
                        brandCue: identified.brandCue
                    )
                    return (index, item)
                }
            }
            var pairs: [(Int, MealItem)] = []
            for await pair in group { pairs.append(pair) }
            return pairs
        }
        let mealItems = indexedItems.sorted { $0.0 < $1.0 }.map(\.1)

        return MealEntry(
            mealName: identification.mealName,
            plateContext: identification.plateContext,
            referenceObjectPresent: identification.referenceObjectPresent,
            overallConfidence: identification.overallConfidence,
            items: mealItems
        )
    }

    // Normalize the Gemini portion to grams. For cup/slice/piece we don't have a generic conversion,
    // so we fall back to a crude category default. Layer 3 (portion calibration) will replace this.
    private func normalizedGrams(for item: IdentifiedItem) -> Double {
        if let gpu = item.portionUnit.gramsPerUnit {
            return item.portionAmount * gpu
        }
        switch item.portionUnit {
        case .cup: return item.portionAmount * 240.0
        case .slice: return item.portionAmount * 30.0
        case .piece: return item.portionAmount * 50.0
        default: return item.portionAmount
        }
    }
}
