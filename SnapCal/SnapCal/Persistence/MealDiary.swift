import Foundation
import Observation

// User-visible meal log. Every saved MealEntry lands here, gets appended to
// meals.jsonl in Application Support, and becomes the Today screen's data.
// Parallel to CorrectionLog but distinct purpose: CorrectionLog is silent
// telemetry for the model; MealDiary is the user's food record.

@MainActor
@Observable
final class MealDiary {
    static let shared = MealDiary()

    private(set) var todaysMeals: [MealEntry] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SnapCal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("meals.jsonl")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        loadToday()
    }

    // Read all meals from disk and keep today's for the UI.
    // v1 is fine to scan the whole file on launch; switch to a dated rollover
    // if the file grows past a few MB.
    private func loadToday() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let lines = data.split(separator: 0x0A)
        let cal = Calendar.current
        var today: [MealEntry] = []
        for line in lines {
            guard let entry = try? decoder.decode(MealEntry.self, from: Data(line)) else { continue }
            if cal.isDateInToday(entry.capturedAt) {
                today.append(entry)
            }
        }
        todaysMeals = today.sorted { $0.capturedAt < $1.capturedAt }
    }

    func save(_ meal: MealEntry) {
        guard let line = try? encoder.encode(meal) else { return }
        var payload = line
        payload.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: payload)
            }
        } else {
            _ = try? payload.write(to: fileURL)
        }
        if Calendar.current.isDateInToday(meal.capturedAt) {
            // Keep list ordered by time.
            var next = todaysMeals
            next.append(meal)
            next.sort { $0.capturedAt < $1.capturedAt }
            todaysMeals = next
        }
        // Mirror to Apple Health if connected. Best-effort, no-op if the
        // user hasn't granted nutrition write permission yet.
        let totals = meal.totals
        let mealId = meal.id
        let capturedAt = meal.capturedAt
        Task {
            await HealthKitService.shared.writeMeal(
                calories: totals.calories,
                proteinGrams: totals.proteinGrams,
                carbGrams: totals.carbGrams,
                fatGrams: totals.fatGrams,
                at: capturedAt,
                mealId: mealId
            )
        }
    }

    var dailyTotals: NutritionFacts {
        todaysMeals.map(\.totals).reduce(.zero, +)
    }

    // All-time meal count, read straight from the jsonl. Cheap enough for
    // the Profile stats card; rescan on demand since logs are small.
    var allTimeMealCount: Int {
        guard let data = try? Data(contentsOf: fileURL) else { return 0 }
        return data.split(separator: 0x0A, omittingEmptySubsequences: true).count
    }

    // Consecutive days ending today where at least one meal was logged.
    // "Today" counts as day 1 even if empty so the streak reads correctly
    // before the user's first meal of the day.
    var dayStreak: Int {
        guard let data = try? Data(contentsOf: fileURL) else { return 0 }
        let cal = Calendar.current
        var dates: Set<Date> = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let entry = try? decoder.decode(MealEntry.self, from: Data(line)) else { continue }
            dates.insert(cal.startOfDay(for: entry.capturedAt))
        }
        if dates.isEmpty { return 0 }

        var streak = 0
        var cursor = cal.startOfDay(for: .now)
        // If nothing logged today, start counting from yesterday — today is
        // still "in progress" and shouldn't break a multi-day streak.
        if !dates.contains(cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor) else {
                return 0
            }
            cursor = yesterday
        }
        while dates.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    // Full meal history read from disk. Used by Insights for trends and
    // most-logged foods. Small log so we rescan on demand.
    func allMeals() -> [MealEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        var out: [MealEntry] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let entry = try? decoder.decode(MealEntry.self, from: Data(line)) {
                out.append(entry)
            }
        }
        return out.sorted { $0.capturedAt < $1.capturedAt }
    }

    // Remove a meal from today's list and rewrite meals.jsonl without that
    // entry. Older days are preserved. Used by swipe-to-delete on Today.
    func delete(_ meal: MealEntry) {
        guard Calendar.current.isDateInToday(meal.capturedAt) else { return }

        todaysMeals.removeAll { $0.id == meal.id }

        guard let data = try? Data(contentsOf: fileURL) else { return }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var kept = Data()
        for line in lines {
            if let entry = try? decoder.decode(MealEntry.self, from: Data(line)),
               entry.id == meal.id {
                continue
            }
            kept.append(Data(line))
            kept.append(0x0A)
        }
        try? kept.write(to: fileURL, options: .atomic)
    }
}
