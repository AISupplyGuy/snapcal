import Foundation

// Layer 3 portion calibration. Reads the silent CorrectionLog (slider
// adjustments the user has made) and produces a rolling per-food ratio
// of correctedGrams/originalGrams. When the user has adjusted the same
// food 5+ times, we assume they've established a personal baseline and
// pre-scale new photos' gramsEstimate before they see the meal card.
//
// The food key is stable across small naming drift:
//   - USDA match → "usda:<fdcId>"
//   - Chain match → "<slug>:<normalized name>" (e.g. "bjs:chocolate chunk pizookie")
//   - No match   → "name:<normalized name>"
//
// Only the last `windowSize` events per food are averaged so old bad
// guesses fade out as the user keeps using the app.

struct PortionCalibration: Sendable {
    static let minCorrections = 5
    static let windowSize = 10

    // Per-key ratio. Access through `ratio(for:)` — unknown keys return nil.
    private let ratios: [String: Double]

    init(events: [CorrectionEvent]) {
        var byKey: [String: [CorrectionEvent]] = [:]
        for event in events {
            let key = Self.foodKey(
                usdaFdcId: event.usdaFdcId,
                matchedSourceId: event.matchedSourceId,
                name: event.foodName
            )
            byKey[key, default: []].append(event)
        }

        var computed: [String: Double] = [:]
        for (key, all) in byKey {
            let recent = Array(all.suffix(Self.windowSize))
            guard recent.count >= Self.minCorrections else { continue }
            let ratios = recent.compactMap { event -> Double? in
                guard event.originalGrams > 0, event.correctedGrams > 0 else { return nil }
                return event.correctedGrams / event.originalGrams
            }
            guard !ratios.isEmpty else { continue }
            let mean = ratios.reduce(0, +) / Double(ratios.count)
            // Clamp to a sane band — a single outlier shouldn't push us 10x.
            computed[key] = max(0.25, min(4.0, mean))
        }
        self.ratios = computed
    }

    func ratio(for item: MealItem) -> Double? {
        let key = Self.foodKey(
            usdaFdcId: item.usdaFdcId,
            matchedSourceId: item.matchedSourceId,
            name: item.name
        )
        return ratios[key]
    }

    static func foodKey(usdaFdcId: Int?, matchedSourceId: String?, name: String) -> String {
        if let id = usdaFdcId { return "usda:\(id)" }
        if let src = matchedSourceId, !src.isEmpty, src != "usda" {
            return "\(src):\(normalize(name))"
        }
        return "name:\(normalize(name))"
    }

    private static func normalize(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
