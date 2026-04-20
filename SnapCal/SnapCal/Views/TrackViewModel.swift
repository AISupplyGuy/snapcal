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

                // Build the router. USDA is always present; chain-menu only wires up
                // if SUPABASE_URL + SUPABASE_ANON_KEY are configured in the scheme.
                var sources: [NutritionSource] = []
                if let chain = try? ChainMenuSource() {
                    sources.append(chain)
                }
                let usdaService = try USDAService()
                sources.append(USDASource(service: usdaService))
                let router = NutritionRouter(sources: sources)

                let pipeline = MealAnalysisPipeline(gemini: gemini, router: router)
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

    func reset() {
        runningTask?.cancel()
        runningTask = nil
        capturedPhoto = nil
        originalMeal = nil
        state = .idle
    }

    // Called when user accepts corrections from the meal card slider(s).
    // Logs every diff silently into CorrectionLog — never shown to the user.
    func commitCorrections(_ updated: MealEntry) {
        guard let original = originalMeal else { return }
        for (old, new) in zip(original.items, updated.items) where old.gramsEstimate != new.gramsEstimate {
            let event = CorrectionEvent(
                id: UUID(),
                loggedAt: .now,
                mealEntryId: updated.id,
                mealItemId: new.id,
                photoFilename: updated.photoFilename,
                foodName: new.name,
                usdaFdcId: new.usdaFdcId,
                originalGrams: old.gramsEstimate,
                correctedGrams: new.gramsEstimate,
                originalNutrition: old.nutrition,
                correctedNutrition: new.nutrition
            )
            Task { await CorrectionLog.shared.record(event) }
        }
        state = .ready(updated)
        originalMeal = updated
    }
}
