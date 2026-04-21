import Foundation
import Observation

// Persists UserGoals to UserDefaults as JSON. Lightweight — goals are a
// handful of doubles, no need for a separate file like MealDiary uses.
@MainActor
@Observable
final class GoalsStore {
    static let shared = GoalsStore()

    private let defaultsKey = "SnapCal.UserGoals.v1"

    private(set) var goals: UserGoals

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(UserGoals.self, from: data) {
            self.goals = decoded.clamped()
        } else {
            self.goals = .default
        }
    }

    func update(_ next: UserGoals) {
        let clamped = next.clamped()
        goals = clamped
        if let data = try? JSONEncoder().encode(clamped) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func resetToDefaults() {
        update(.default)
    }
}
