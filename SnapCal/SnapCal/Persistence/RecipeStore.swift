import Foundation
import Observation

// Local cache of recently-generated recipes plus the user's saved set.
// Same jsonl shape as MealDiary / PantryStore so a future export task
// can ship one helper across all three. Three buckets:
//
//   • `recents` — last N generations, displayed as the Cook tab's deck.
//     Capped at 20 so we don't grow forever.
//   • `saved` — the recipes the user explicitly hearted; survives recents
//     truncation and shows up under "Saved" in the Cook nav bar.
//   • `generationsToday` — the day's free-tier counter; resets on the
//     local-calendar day flip.
@MainActor
@Observable
final class RecipeStore {
    static let shared = RecipeStore()

    private(set) var recents: [Recipe] = []
    private(set) var saved: [Recipe] = []
    private(set) var generationsToday: Int = 0

    static let dailyFreeGenerations = 1
    static let recentsCap = 20

    private let recentsURL: URL
    private let savedURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let defaults = UserDefaults.standard
    private let counterKey = "recipe.generations.today"
    private let counterDayKey = "recipe.generations.day"

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SnapCal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.recentsURL = dir.appendingPathComponent("recipes.recent.jsonl")
        self.savedURL = dir.appendingPathComponent("recipes.saved.jsonl")
        self.encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        rolloverIfNeeded()
        generationsToday = defaults.integer(forKey: counterKey)
        recents = load(from: recentsURL)
        saved = load(from: savedURL)
    }

    // MARK: Generation gate

    func canGenerate() -> Bool {
        if Subscriptions.shared.isPro { return true }
        rolloverIfNeeded()
        return defaults.integer(forKey: counterKey) < Self.dailyFreeGenerations
    }

    func recordGeneration() {
        rolloverIfNeeded()
        let next = defaults.integer(forKey: counterKey) + 1
        defaults.set(next, forKey: counterKey)
        generationsToday = next
    }

    var generationsRemainingToday: Int {
        if Subscriptions.shared.isPro { return .max }
        return max(0, Self.dailyFreeGenerations - generationsToday)
    }

    // MARK: Recents

    func record(_ recipe: Recipe) {
        var next = [recipe] + recents.filter { $0.id != recipe.id }
        if next.count > Self.recentsCap {
            next = Array(next.prefix(Self.recentsCap))
        }
        recents = next
        rewrite(recents, to: recentsURL)
    }

    // MARK: Saved

    func toggleSaved(_ recipe: Recipe) {
        if let idx = saved.firstIndex(where: { $0.id == recipe.id }) {
            saved.remove(at: idx)
        } else {
            saved.insert(recipe, at: 0)
        }
        rewrite(saved, to: savedURL)
    }

    func isSaved(_ recipe: Recipe) -> Bool {
        saved.contains(where: { $0.id == recipe.id })
    }

    // MARK: I/O

    private func load(from url: URL) -> [Recipe] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        var out: [Recipe] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let r = try? decoder.decode(Recipe.self, from: Data(line)) {
                out.append(r)
            }
        }
        return out
    }

    private func rewrite(_ list: [Recipe], to url: URL) {
        var data = Data()
        for r in list {
            guard let line = try? encoder.encode(r) else { continue }
            data.append(line); data.append(0x0A)
        }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Counter rollover

    private func rolloverIfNeeded() {
        let today = UsageMeter.dayString(for: .now)
        if defaults.string(forKey: counterDayKey) != today {
            defaults.set(today, forKey: counterDayKey)
            defaults.set(0, forKey: counterKey)
            generationsToday = 0
        }
    }
}
