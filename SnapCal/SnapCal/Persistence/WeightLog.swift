import Foundation
import Observation

// Append-only log of weight measurements, mirrors MealDiary's jsonl
// pattern. Observed so Track + Insights re-render when a new entry
// lands. In-memory cache avoids rereading on every access.
@MainActor
@Observable
final class WeightLog {
    static let shared = WeightLog()

    private(set) var entries: [WeightEntry] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = appSupport.appendingPathComponent("SnapCal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("weights.jsonl")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        loadAll()
    }

    private func loadAll() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        var out: [WeightEntry] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let entry = try? decoder.decode(WeightEntry.self, from: Data(line)) {
                out.append(entry)
            }
        }
        entries = out.sorted { $0.measuredAt < $1.measuredAt }
    }

    func log(_ entry: WeightEntry) {
        guard let line = try? encoder.encode(entry) else { return }
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
        var next = entries
        next.append(entry)
        next.sort { $0.measuredAt < $1.measuredAt }
        entries = next
    }

    // Remove the most recent entry (usually to correct a typo right after
    // logging). No bulk delete — keeping the history.
    func undoLast() {
        guard let last = entries.last else { return }
        remove(last)
    }

    private func remove(_ entry: WeightEntry) {
        entries.removeAll { $0.id == entry.id }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        var kept = Data()
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let decoded = try? decoder.decode(WeightEntry.self, from: Data(line)),
               decoded.id == entry.id {
                continue
            }
            kept.append(Data(line))
            kept.append(0x0A)
        }
        try? kept.write(to: fileURL, options: .atomic)
    }

    var latest: WeightEntry? { entries.last }

    // Change vs the oldest entry within the last `days` window. Positive
    // means up from baseline; nil if there's not enough data yet.
    func change(overLastDays days: Int, unit: WeightUnit) -> Double? {
        guard let latest else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: latest.measuredAt) ?? latest.measuredAt
        let window = entries.filter { $0.measuredAt >= cutoff }
        guard let first = window.first, first.id != latest.id else { return nil }
        let deltaKg = latest.kilograms - first.kilograms
        switch unit {
        case .kilograms: return deltaKg
        case .pounds:    return deltaKg * 2.20462
        }
    }
}
