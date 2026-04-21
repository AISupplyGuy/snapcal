import Foundation

// Daily targets that drive the rings on Today and the progress math
// everywhere else. Defaults are sensible adult-average starting points;
// the user can change any of these in Profile.
struct UserGoals: Codable, Sendable, Equatable {
    var calories: Double
    var proteinGrams: Double
    var carbGrams: Double
    var fatGrams: Double
    var fiberGrams: Double

    static let `default` = UserGoals(
        calories: 2200,
        proteinGrams: 150,
        carbGrams: 250,
        fatGrams: 70,
        fiberGrams: 30
    )

    // Clamp to reasonable human ranges so a typo can't produce a ring that
    // fills on crumbs or never fills at all.
    func clamped() -> UserGoals {
        UserGoals(
            calories: min(max(calories, 800), 6000),
            proteinGrams: min(max(proteinGrams, 20), 400),
            carbGrams: min(max(carbGrams, 20), 800),
            fatGrams: min(max(fatGrams, 10), 300),
            fiberGrams: min(max(fiberGrams, 5), 100)
        )
    }
}
