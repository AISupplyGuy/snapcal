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
    // Non-USDA source identifier (e.g. "bjs", "chipotle"). Needed so portion
    // calibration can tell "BJ's Pizookie" apart from a generic chocolate chip
    // cookie under the same display name. Added after v1 ships, so Codable
    // decodes missing values as nil.
    let matchedSourceId: String?
    let originalGrams: Double
    let correctedGrams: Double
    let originalNutrition: NutritionFacts
    let correctedNutrition: NutritionFacts

    init(
        id: UUID,
        loggedAt: Date,
        mealEntryId: UUID,
        mealItemId: UUID,
        photoFilename: String?,
        foodName: String,
        usdaFdcId: Int?,
        matchedSourceId: String? = nil,
        originalGrams: Double,
        correctedGrams: Double,
        originalNutrition: NutritionFacts,
        correctedNutrition: NutritionFacts
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.mealEntryId = mealEntryId
        self.mealItemId = mealItemId
        self.photoFilename = photoFilename
        self.foodName = foodName
        self.usdaFdcId = usdaFdcId
        self.matchedSourceId = matchedSourceId
        self.originalGrams = originalGrams
        self.correctedGrams = correctedGrams
        self.originalNutrition = originalNutrition
        self.correctedNutrition = correctedNutrition
    }

    private enum CodingKeys: String, CodingKey {
        case id, loggedAt, mealEntryId, mealItemId, photoFilename, foodName
        case usdaFdcId, matchedSourceId, originalGrams, correctedGrams
        case originalNutrition, correctedNutrition
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.loggedAt = try c.decode(Date.self, forKey: .loggedAt)
        self.mealEntryId = try c.decode(UUID.self, forKey: .mealEntryId)
        self.mealItemId = try c.decode(UUID.self, forKey: .mealItemId)
        self.photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
        self.foodName = try c.decode(String.self, forKey: .foodName)
        self.usdaFdcId = try c.decodeIfPresent(Int.self, forKey: .usdaFdcId)
        self.matchedSourceId = try c.decodeIfPresent(String.self, forKey: .matchedSourceId)
        self.originalGrams = try c.decode(Double.self, forKey: .originalGrams)
        self.correctedGrams = try c.decode(Double.self, forKey: .correctedGrams)
        self.originalNutrition = try c.decode(NutritionFacts.self, forKey: .originalNutrition)
        self.correctedNutrition = try c.decode(NutritionFacts.self, forKey: .correctedNutrition)
    }
}

actor CorrectionLog {
    static let shared = CorrectionLog()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cache: [CorrectionEvent]?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SnapCal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("corrections.jsonl")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
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
        if cache != nil { cache?.append(event) }
    }

    // All corrections ever logged, loaded from disk on first call and kept
    // warm thereafter. Portion calibration reads this to compute rolling
    // per-food ratios.
    func allEvents() -> [CorrectionEvent] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL) else {
            cache = []
            return []
        }
        var events: [CorrectionEvent] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let event = try? decoder.decode(CorrectionEvent.self, from: Data(line)) {
                events.append(event)
            }
        }
        cache = events
        return events
    }
}
