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
    private var originalMeal: MealEntry?

    func analyze(image: UIImage) {
        state = .analyzing
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            state = .failed("Couldn't encode photo.")
            return
        }
        Task {
            do {
                let gemini = try GeminiService()
                let usda = try USDAService()
                let pipeline = MealAnalysisPipeline(gemini: gemini, usda: usda)
                let meal = try await pipeline.analyze(imageJPEG: jpeg)
                self.originalMeal = meal
                self.state = .ready(meal)
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
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
