import Foundation

// Turns the raw MealDiary into the shapes the Insights tab needs.
// Pure functions — the UI calls this once per view appear and re-renders.

struct DailyTotal: Identifiable, Sendable {
    let id: Date       // start-of-day
    let date: Date
    let totals: NutritionFacts
    var calories: Double { totals.calories }
}

struct FoodCount: Identifiable, Sendable {
    let id: String     // stable food key
    let name: String
    let count: Int
    let lastSeen: Date
}

struct InsightsSnapshot: Sendable {
    let days: [DailyTotal]                 // last N days, oldest → newest (missing days zero-filled)
    let averageCalories: Double            // mean of the days that actually had meals
    let averageProtein: Double
    let averageCarbs: Double
    let averageFat: Double
    let goalAttainmentStreak: Int          // consecutive days within ±10% of calorie goal
    let dayStreak: Int                     // consecutive logging days (from MealDiary)
    let mostLogged: [FoodCount]            // top N foods by appearance
    let totalMealsLogged: Int
}

enum InsightsAggregator {

    // Compute a snapshot over the last `windowDays` including today.
    static func snapshot(
        meals: [MealEntry],
        goals: UserGoals,
        dayStreak: Int,
        now: Date = .now,
        windowDays: Int = 7,
        topFoods: Int = 5
    ) -> InsightsSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        // Group meals by day.
        var byDay: [Date: NutritionFacts] = [:]
        for meal in meals {
            let day = cal.startOfDay(for: meal.capturedAt)
            byDay[day, default: .zero] = byDay[day, default: .zero] + meal.totals
        }

        // Build a dense window: one entry per day, zero-filled.
        var days: [DailyTotal] = []
        for offset in stride(from: windowDays - 1, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let totals = byDay[date] ?? .zero
            days.append(DailyTotal(id: date, date: date, totals: totals))
        }

        // Average over days that actually had any meals — counting empty days
        // would make averages meaningless during onboarding.
        let active = days.filter { $0.calories > 0 }
        func mean(_ picker: (NutritionFacts) -> Double) -> Double {
            guard !active.isEmpty else { return 0 }
            let sum = active.map { picker($0.totals) }.reduce(0, +)
            return sum / Double(active.count)
        }

        // Goal attainment: consecutive days ending today within ±10% of the
        // calorie goal. "Today" only counts if the ring's already hit ≥90% of
        // goal — being under the low-water mark with the day still open
        // shouldn't break a streak.
        var goalStreak = 0
        let lowerBand = goals.calories * 0.9
        let upperBand = goals.calories * 1.1
        for (i, day) in days.reversed().enumerated() {
            let inBand = day.calories >= lowerBand && day.calories <= upperBand
            let dayIsToday = cal.isDate(day.date, inSameDayAs: today)
            if i == 0 && dayIsToday {
                // Give today a pass if it's still open (below upper band but
                // also below lower — day in progress).
                if day.calories < lowerBand {
                    continue
                }
            }
            if inBand {
                goalStreak += 1
            } else {
                break
            }
        }

        // Most-logged foods — group by the same key PortionCalibration uses
        // so display lines up with what calibration is actually learning.
        var counts: [String: (name: String, count: Int, lastSeen: Date)] = [:]
        for meal in meals {
            for item in meal.items {
                let key = PortionCalibration.foodKey(
                    usdaFdcId: item.usdaFdcId,
                    matchedSourceId: item.matchedSourceId,
                    name: item.name
                )
                if let existing = counts[key] {
                    counts[key] = (
                        existing.name,
                        existing.count + 1,
                        max(existing.lastSeen, meal.capturedAt)
                    )
                } else {
                    counts[key] = (item.name, 1, meal.capturedAt)
                }
            }
        }
        let mostLogged = counts
            .map { FoodCount(id: $0.key, name: $0.value.name, count: $0.value.count, lastSeen: $0.value.lastSeen) }
            .sorted { $0.count > $1.count }
            .prefix(topFoods)

        return InsightsSnapshot(
            days: days,
            averageCalories: mean(\.calories),
            averageProtein: mean(\.proteinGrams),
            averageCarbs: mean(\.carbGrams),
            averageFat: mean(\.fatGrams),
            goalAttainmentStreak: goalStreak,
            dayStreak: dayStreak,
            mostLogged: Array(mostLogged),
            totalMealsLogged: meals.count
        )
    }
}
