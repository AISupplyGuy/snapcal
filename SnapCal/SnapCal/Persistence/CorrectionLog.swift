import Foundation

// Silent log of every portion/nutrition correction the user makes.
// Per ARCHITECTURE.md Layer 4: "log everything silently from day one. The dataset compounds."
// v1 writes JSONL to Application Support. Migrate to Core Data / Supabase in v1.1+.

struct CorrectionEvent: Codable, Sendable {
    let id: UUID
    let loggedAt: Date
    let mealEntryId: UUID
    let mealItemId: UUID
    let photoFilename: String?
    let foodName: String
    let usdaFdcId: Int?
    let originalGrams: Double
    let correctedGrams: Double
    let originalNutrition: NutritionFacts
    let correctedNutrition: NutritionFacts
}

actor CorrectionLog {
    static let shared = CorrectionLog()

    private let fileURL: URL
    private let encoder: JSONEncoder

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SnapCal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("corrections.jsonl")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func record(_ event: CorrectionEvent) {
        guard let line = try? encoder.encode(event) else { return }
        var payload = line
        payload.append(0x0A) // newline
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: payload)
            }
        } else {
            try? payload.write(to: fileURL)
        }
    }
}
