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
    }

    var dailyTotals: NutritionFacts {
        todaysMeals.map(\.totals).reduce(.zero, +)
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
