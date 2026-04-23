import Foundation
import Observation

// Single source of truth for what's in the user's pantry. Same jsonl
// pattern MealDiary / WeightLog use — small log, full in-memory cache,
// rewrite on delete/update.
@MainActor
@Observable
final class PantryStore {
    static let shared = PantryStore()

    private(set) var items: [PantryItem] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = appSupport.appendingPathComponent("SnapCal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("pantry.jsonl")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        loadAll()
    }

    private func loadAll() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        var out: [PantryItem] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let item = try? decoder.decode(PantryItem.self, from: Data(line)) {
                out.append(item)
            }
        }
        items = sorted(out)
    }

    func add(_ item: PantryItem) {
        items = sorted(items + [item])
        rewrite()
    }

    func update(_ updated: PantryItem) {
        var next = items
        if let i = next.firstIndex(where: { $0.id == updated.id }) {
            var copy = updated
            copy.updatedAt = .now
            next[i] = copy
        } else {
            next.append(updated)
        }
        items = sorted(next)
        rewrite()
    }

    func delete(_ item: PantryItem) {
        items.removeAll { $0.id == item.id }
        rewrite()
    }

    // Items by category, oldest-added first within each category so the
    // pantry list has a stable order.
    func grouped() -> [(category: PantryCategory, items: [PantryItem])] {
        let buckets = Dictionary(grouping: items, by: { $0.category })
        return PantryCategory.allCases.compactMap { cat in
            guard let list = buckets[cat], !list.isEmpty else { return nil }
            return (cat, list)
        }
    }

    private func sorted(_ list: [PantryItem]) -> [PantryItem] {
        list.sorted { ($0.addedAt, $0.name.lowercased()) < ($1.addedAt, $1.name.lowercased()) }
    }

    private func rewrite() {
        var payload = Data()
        for item in items {
            guard let line = try? encoder.encode(item) else { continue }
            payload.append(line)
            payload.append(0x0A)
        }
        try? payload.write(to: fileURL, options: .atomic)
    }
}
