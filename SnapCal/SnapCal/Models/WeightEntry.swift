import Foundation

// User-logged body weight measurement. Stored in kg internally; UI
// converts on display based on user preference (lbs default for US).
// Later this file gets superseded by HealthKit reads, but we still keep
// the local log as a fallback + offline buffer.
struct WeightEntry: Codable, Sendable, Identifiable {
    let id: UUID
    var measuredAt: Date
    var kilograms: Double
    var note: String?

    var pounds: Double { kilograms * 2.20462 }

    init(
        id: UUID = UUID(),
        measuredAt: Date = .now,
        kilograms: Double,
        note: String? = nil
    ) {
        self.id = id
        self.measuredAt = measuredAt
        self.kilograms = kilograms
        self.note = note
    }
}

enum WeightUnit: String, Sendable, CaseIterable, Identifiable {
    case pounds, kilograms
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pounds:     return "lbs"
        case .kilograms:  return "kg"
        }
    }
}
