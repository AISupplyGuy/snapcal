import SwiftUI
import UIKit

@MainActor
@Observable
final class TrackViewModel {
    enum State {
        case idle
        case analyzing
        case ready(MealEntry)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var capturedPhoto: UIImage?
    private var originalMeal: MealEntry?
    private var runningTask: Task<Void, Never>?

    func analyze(image: UIImage) {
        capturedPhoto = image
        state = .analyzing
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            state = .failed("Couldn't encode photo.")
            return
        }
        runningTask?.cancel()
        runningTask = Task {
            do {
                let gemini = try GeminiService()
                let (router, chainMenu) = try self.buildRouter()

                let pipeline = MealAnalysisPipeline(
                    gemini: gemini,
                    router: router,
                    chainMenu: chainMenu
                )
                let meal = try await pipeline.analyze(imageJPEG: jpeg)
                if Task.isCancelled { return }
                self.originalMeal = meal
                self.state = .ready(meal)
            } catch {
                if Task.isCancelled { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func rematchDietaryVariant(
        for item: MealItem,
        preference: DietaryVariantPreference,
        plateContext: PlateContext
    ) async -> NutritionMatch? {
        guard item.matchedSourceId != "usda" else { return nil }
        let queryName = dietaryAdjustedQueryName(from: item.name, preference: preference)
        guard !queryName.isEmpty else { return nil }
        let brandCue: String? = { () -> String? in
            if let cue = item.brandCue, !cue.isEmpty { return cue }
            switch item.matchedSourceId {
            case "bjs": return "BJ's"
            case "chipotle": return "Chipotle"
            case "mcdonalds": return "McDonald's"
            case "starbucks": return "Starbucks"
            case "wendys": return "Wendy's"
            case "panera": return "Panera"
            case "shakeshack": return "Shake Shack"
            case "chicagofire": return "Chicago Fire"
            default: return nil
            }
        }()
        guard let brandCue, !brandCue.isEmpty else { return nil }
        guard let router = (try? buildRouter())?.0 else { return nil }

        let query = NutritionQuery(
            itemName: queryName,
            brandCue: brandCue,
            gramsEstimate: item.gramsEstimate,
            plateContext: plateContext
        )
        return await router.lookup(query: query)
    }

    func rematchSizeVariant(
        for item: MealItem,
        sizeKey: String,
        plateContext: PlateContext
    ) async -> NutritionMatch? {
        guard item.matchedSourceId != "usda" else { return nil }
        guard let router = (try? buildRouter())?.0 else { return nil }
        let queryName = ChainVariantSupport.adjustedQueryName(for: item, targetSizeKey: sizeKey)
        guard !queryName.isEmpty else { return nil }

        let brandCue: String? = { () -> String? in
            if let cue = item.brandCue, !cue.isEmpty { return cue }
            switch item.matchedSourceId {
            case "bjs": return "BJ's"
            case "chipotle": return "Chipotle"
            case "mcdonalds": return "McDonald's"
            case "starbucks": return "Starbucks"
            case "wendys": return "Wendy's"
            case "panera": return "Panera"
            case "shakeshack": return "Shake Shack"
            case "chicagofire": return "Chicago Fire"
            default: return nil
            }
        }()
        guard let brandCue, !brandCue.isEmpty else { return nil }

        let query = NutritionQuery(
            itemName: queryName,
            brandCue: brandCue,
            gramsEstimate: item.gramsEstimate,
            plateContext: plateContext
        )
        return await router.lookup(query: query)
    }

    // Async fetch of the chain list that backs the "From" picker on the meal
    // card. Falls back to an empty array if Supabase is unreachable so the
    // picker just shows "Home".
    func loadSupportedChains() async -> [Chain] {
        guard let chainMenu = try? ChainMenuSource() else { return [] }
        return await chainMenu.supportedChains()
    }

    // Re-match a single item against a user-declared chain. Returns nil if
    // the chain doesn't have a matching menu item (caller should keep the
    // original item in that case). No brandCue in the photo required — the
    // picker itself is the signal.
    func rematchForChain(
        item: MealItem,
        chainName: String,
        plateContext: PlateContext
    ) async -> NutritionMatch? {
        guard let chainMenu = try? ChainMenuSource() else { return nil }
        let query = NutritionQuery(
            itemName: chainMealQueryName(for: item),
            brandCue: chainName,
            gramsEstimate: item.gramsEstimate,
            plateContext: plateContext
        )
        return try? await chainMenu.lookup(query: query)
    }

    // Strip generic modifiers Gemini adds ("baked", "with vanilla ice cream")
    // before handing to the chain search — chain menu names are terser.
    private func chainMealQueryName(for item: MealItem) -> String {
        let stripped = item.name
            .replacingOccurrences(of: "(?i),?\\s*baked\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\bwith .*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? item.name : stripped
    }

    func reset() {
        runningTask?.cancel()
        runningTask = nil
        capturedPhoto = nil
        originalMeal = nil
        state = .idle
    }

    // Used by the meal card's chain picker when the user resets to "Home" —
    // returns the original items as produced by the pipeline.
    var pristineItems: [MealItem]? { originalMeal?.items }

    // Called when the user taps Save on the meal card. Persists the meal to the
    // user-visible diary, writes any slider edits to CorrectionLog (silent
    // model-training telemetry), and drops back to the Today screen.
    func commitCorrections(_ updated: MealEntry) {
        if let original = originalMeal {
            for (old, new) in zip(original.items, updated.items) where old.gramsEstimate != new.gramsEstimate {
                let event = CorrectionEvent(
                    id: UUID(),
                    loggedAt: .now,
                    mealEntryId: updated.id,
                    mealItemId: new.id,
                    photoFilename: updated.photoFilename,
                    foodName: new.name,
                    usdaFdcId: new.usdaFdcId,
                    matchedSourceId: new.matchedSourceId,
                    originalGrams: old.gramsEstimate,
                    correctedGrams: new.gramsEstimate,
                    originalNutrition: old.nutrition,
                    correctedNutrition: new.nutrition
                )
                Task { await CorrectionLog.shared.record(event) }
            }
        }
        MealDiary.shared.save(updated)
        reset()
    }

    // Returns the router plus the ChainMenuSource it was built around (or nil
    // if Supabase env isn't configured). The pipeline needs the chain source
    // directly to fetch the live supported-chains list for the Gemini prompt,
    // so we hand it out alongside the router rather than reconstructing it.
    private func buildRouter() throws -> (NutritionRouter, ChainMenuSource?) {
        var sources: [NutritionSource] = []
        let chain = try? ChainMenuSource()
        if let chain {
            sources.append(chain)
        }
        let usdaService = try USDAService()
        sources.append(USDASource(service: usdaService))
        return (NutritionRouter(sources: sources), chain)
    }

    private func dietaryAdjustedQueryName(
        from name: String,
        preference: DietaryVariantPreference
    ) -> String {
        let stripped = name
            .replacingOccurrences(of: "(?i)\\bgluten\\s*-?\\s*free\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\bgf\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch preference {
        case .unknown:
            return stripped
        case .glutenFree:
            return "\(stripped) gluten free"
        case .notGlutenFree:
            return stripped
        }
    }
}
