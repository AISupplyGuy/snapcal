import Foundation

// The user's weight goal. Kept separate from UserGoals (calorie/macro
// targets) — those are nutrition-side and live in Profile; this is the
// longer-arc outcome target that the Goals card on Track celebrates.
struct WeightGoal: Codable, Sendable, Equatable {
    var direction: Direction
    var startingKilograms: Double        // baseline snapshot when the goal was set
    var targetKilograms: Double
    var weeklyRateKilograms: Double      // kg/week target pace (signed by direction)
    var startDate: Date

    enum Direction: String, Codable, Sendable, CaseIterable, Identifiable {
        case lose, maintain, gain
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lose:     return "Lose"
            case .maintain: return "Maintain"
            case .gain:     return "Gain"
            }
        }
    }

    // Fraction (0-1) of the gap that's been closed. Works for both
    // directions; .maintain always returns 1 while the user is inside
    // a ±2kg tolerance band, 0 otherwise (shown differently in the UI).
    func progress(currentKilograms current: Double) -> Double {
        switch direction {
        case .lose:
            let span = startingKilograms - targetKilograms
            guard span > 0 else { return 1 }
            return max(0, min(1, (startingKilograms - current) / span))
        case .gain:
            let span = targetKilograms - startingKilograms
            guard span > 0 else { return 1 }
            return max(0, min(1, (current - startingKilograms) / span))
        case .maintain:
            return abs(current - targetKilograms) <= 2 ? 1 : 0
        }
    }

    // Weeks of tracking since the goal was set.
    func weeksElapsed(now: Date = .now) -> Double {
        let days = now.timeIntervalSince(startDate) / 86400
        return max(0, days / 7)
    }

    // Observed kg/week pace since start, using the latest reading.
    func observedWeeklyPace(currentKilograms current: Double, now: Date = .now) -> Double {
        let weeks = weeksElapsed(now: now)
        guard weeks >= 0.5 else { return 0 }
        return (current - startingKilograms) / weeks
    }
}
