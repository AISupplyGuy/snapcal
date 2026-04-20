import Foundation

// Orchestrates: photo → Gemini identification → USDA lookup per item → MealEntry with computed totals.
// The model never supplies calorie numbers. This pipeline is the only path that writes nutrition.
actor MealAnalysisPipeline {
    private let gemini: GeminiService
    private let usda: USDAService

    init(gemini: GeminiService, usda: USDAService) {
        self.gemini = gemini
        self.usda = usda
    }

    func analyze(imageJPEG: Data) async throws -> MealEntry {
        let identification = try await gemini.identifyMeal(imageJPEG: imageJPEG)

        // USDA lookups run in parallel — network I/O dominates, and the actor
        // is re-entrant while awaiting URLSession. Ordering preserved via index.
        let usdaService = self.usda
        let indexedItems: [(Int, MealItem)] = try await withThrowingTaskGroup(
            of: (Int, MealItem).self
        ) { group in
            for (index, identified) in identification.items.enumerated() {
                let grams = self.normalizedGrams(for: identified)
                group.addTask {
                    let food = try? await usdaService.bestMatch(for: identified.name)
                    let nutrition: NutritionFacts
                    if let food {
                        nutrition = await usdaService.nutrition(for: food, gramsEstimate: grams)
                    } else {
                        nutrition = .zero
                    }
                    let item = MealItem(
                        name: identified.name,
                        portionAmount: identified.portionAmount,
                        portionUnit: identified.portionUnit,
                        gramsEstimate: grams,
                        usdaFdcId: food?.fdcId,
                        usdaDescription: food?.description,
                        nutrition: nutrition,
                        itemConfidence: identified.itemConfidence,
                        preparation: identified.preparation,
                        brandCue: identified.brandCue
                    )
                    return (index, item)
                }
            }
            var pairs: [(Int, MealItem)] = []
            for try await pair in group { pairs.append(pair) }
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
