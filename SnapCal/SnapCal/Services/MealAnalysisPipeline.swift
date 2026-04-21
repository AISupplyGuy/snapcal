import Foundation

// Orchestrates: photo → Gemini identification → NutritionRouter per item → MealEntry with computed totals.
// The model never supplies calorie numbers. The router is the only path that writes nutrition.
actor MealAnalysisPipeline {
    private let gemini: GeminiService
    private let router: NutritionRouter
    private let chainMenu: ChainMenuSource?

    init(gemini: GeminiService, router: NutritionRouter, chainMenu: ChainMenuSource? = nil) {
        self.gemini = gemini
        self.router = router
        self.chainMenu = chainMenu
    }

    // Confidence threshold below which we escalate Flash's result to Pro for
    // a second opinion. Per ARCHITECTURE.md Layer 5: the signal is the
    // model's own `overall_confidence`, not item count or photo complexity.
    private static let confidenceThreshold = 0.7

    // If Flash and Pro disagree on total calories by more than this ratio,
    // the UI asks the user to sanity-check the card before saving.
    private static let divergenceThreshold = 0.25

    func analyze(imageJPEG: Data) async throws -> MealEntry {
        let supportedChains = await chainMenu?.supportedChainNames() ?? []

        // Step 1: Flash call.
        let flashId = try await gemini.identifyMeal(
            imageJPEG: imageJPEG,
            supportedChains: supportedChains
        )
        var mealItems = await resolveItems(for: flashId)
        var modelTier = "flash"
        var needsVerification = false

        // Step 2: escalate to Pro if Flash isn't confident. Skip when the
        // photo is a chain-routed meal (brand_cue set on every item) —
        // chain DB is the source of truth and Pro can't improve that.
        let allBranded = !flashId.items.isEmpty
            && flashId.items.allSatisfy { ($0.brandCue ?? "").isEmpty == false }

        if flashId.overallConfidence < Self.confidenceThreshold && !allBranded {
            #if DEBUG
            print("[Pipeline] Flash confidence \(flashId.overallConfidence) < \(Self.confidenceThreshold) — escalating to Pro")
            #endif
            let proModelName = await gemini.escalationModel
            do {
                let proId = try await gemini.identifyMeal(
                    imageJPEG: imageJPEG,
                    supportedChains: supportedChains,
                    modelOverride: proModelName
                )
                let proItems = await resolveItems(for: proId)

                // Compare totals. If they agree within divergenceThreshold,
                // use Pro's answer silently (Pro is strictly more accurate
                // on the hard cases we're escalating). If they diverge
                // materially, still use Pro but flag for user verification.
                let flashCals = mealItems.map(\.nutrition.calories).reduce(0, +)
                let proCals = proItems.map(\.nutrition.calories).reduce(0, +)
                let denom = max(flashCals, proCals)
                let divergence = denom > 0 ? abs(flashCals - proCals) / denom : 0

                #if DEBUG
                print("[Pipeline] Flash=\(Int(flashCals))cal Pro=\(Int(proCals))cal divergence=\(String(format: "%.2f", divergence))")
                #endif

                mealItems = proItems
                modelTier = divergence > Self.divergenceThreshold ? "flash+pro" : "pro"
                needsVerification = divergence > Self.divergenceThreshold
            } catch {
                #if DEBUG
                print("[Pipeline] Pro escalation failed, keeping Flash: \(error.localizedDescription)")
                #endif
                // Keep Flash's answer on Pro failure — don't block the user
                // on an optional second opinion. Still flag for verification
                // since Flash was low-confidence to begin with.
                needsVerification = true
            }
        }

        return MealEntry(
            mealName: flashId.mealName,
            plateContext: flashId.plateContext,
            referenceObjectPresent: flashId.referenceObjectPresent,
            overallConfidence: flashId.overallConfidence,
            items: mealItems,
            modelTier: modelTier,
            needsVerification: needsVerification
        )
    }

    // Shared per-item USDA/chain lookup. Runs router calls in parallel.
    private func resolveItems(for identification: GeminiMealResponse) async -> [MealItem] {
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
                    let matchedNutrition = match?.nutrition ?? .zero
                    let baselinePer100g: NutritionFacts = grams > 0
                        ? matchedNutrition.scaled(by: 100.0 / grams)
                        : matchedNutrition
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
                        nutrition: matchedNutrition,
                        baselinePer100g: baselinePer100g,
                        itemConfidence: identified.itemConfidence,
                        preparation: identified.preparation,
                        brandCue: identified.brandCue,
                        availableSizeOptions: match?.sizeOptions,
                        selectedSizeKey: match?.selectedSizeKey
                    )
                    return (index, item)
                }
            }
            var pairs: [(Int, MealItem)] = []
            for await pair in group { pairs.append(pair) }
            return pairs
        }
        return indexedItems.sorted { $0.0 < $1.0 }.map(\.1)
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
