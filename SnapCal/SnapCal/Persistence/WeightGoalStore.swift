import Foundation
import Observation

// Persists WeightGoal to UserDefaults. One goal per user at a time; set
// again to overwrite. No history yet — if we need "past goals" later,
// move to a jsonl like MealDiary.
@MainActor
@Observable
final class WeightGoalStore {
    static let shared = WeightGoalStore()

    private let key = "SnapCal.WeightGoal.v1"

    private(set) var goal: WeightGoal?

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder.iso.decode(WeightGoal.self, from: data) {
            goal = decoded
        }
    }

    func set(_ next: WeightGoal) {
        goal = next
        if let data = try? JSONEncoder.iso.encode(next) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        goal = nil
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
