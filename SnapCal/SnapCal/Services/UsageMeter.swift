import Foundation
import Observation

// Daily counter that gates the free tier. Free users get 3 meal scans
// and 1 barcode scan per local-calendar day; Pro is unlimited. Counts
// are persisted in UserDefaults keyed by yyyy-MM-dd so the rollover is
// midnight-local-time without any timer machinery — we just compare
// today's key on every check.
//
// Why daily and not lifetime: a hard lifetime cap converts hot leads but
// kills cold-start retention. A daily cap lets users build the habit
// for a week before hitting the upgrade decision. Industry-standard for
// tracker apps (Cal AI, MacroFactor follow this shape).
@MainActor
@Observable
final class UsageMeter {
    static let shared = UsageMeter()

    static let mealScanDailyLimit = 3
    static let barcodeScanDailyLimit = 1

    private let defaults = UserDefaults.standard
    private let mealKey = "usage.meal.scans"
    private let barcodeKey = "usage.barcode.scans"
    private let dayKey = "usage.day"

    private(set) var mealScansToday: Int = 0
    private(set) var barcodeScansToday: Int = 0

    private init() {
        rolloverIfNeeded()
        mealScansToday = defaults.integer(forKey: mealKey)
        barcodeScansToday = defaults.integer(forKey: barcodeKey)
    }

    // MARK: Gates

    // Returns true if the user can perform another meal scan right now.
    // Pro is always allowed; free is allowed up to mealScanDailyLimit.
    func canMealScan() -> Bool {
        if Subscriptions.shared.isPro { return true }
        rolloverIfNeeded()
        return defaults.integer(forKey: mealKey) < Self.mealScanDailyLimit
    }

    func canBarcodeScan() -> Bool {
        if Subscriptions.shared.isPro { return true }
        rolloverIfNeeded()
        return defaults.integer(forKey: barcodeKey) < Self.barcodeScanDailyLimit
    }

    // MARK: Recording (call AFTER a successful scan reaches the camera /
    // barcode capture, not on the button tap — that way a denied-permission
    // dismiss doesn't burn a free credit.)

    func recordMealScan() {
        rolloverIfNeeded()
        let next = defaults.integer(forKey: mealKey) + 1
        defaults.set(next, forKey: mealKey)
        mealScansToday = next
    }

    func recordBarcodeScan() {
        rolloverIfNeeded()
        let next = defaults.integer(forKey: barcodeKey) + 1
        defaults.set(next, forKey: barcodeKey)
        barcodeScansToday = next
    }

    // MARK: Display helpers

    var mealScansRemaining: Int {
        if Subscriptions.shared.isPro { return .max }
        return max(0, Self.mealScanDailyLimit - mealScansToday)
    }

    var barcodeScansRemaining: Int {
        if Subscriptions.shared.isPro { return .max }
        return max(0, Self.barcodeScanDailyLimit - barcodeScansToday)
    }

    // MARK: Rollover

    private func rolloverIfNeeded() {
        let today = Self.dayString(for: .now)
        let stored = defaults.string(forKey: dayKey)
        if stored != today {
            defaults.set(today, forKey: dayKey)
            defaults.set(0, forKey: mealKey)
            defaults.set(0, forKey: barcodeKey)
            mealScansToday = 0
            barcodeScansToday = 0
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(for date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
