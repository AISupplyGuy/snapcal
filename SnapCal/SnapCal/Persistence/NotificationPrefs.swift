import Foundation
import Observation

// Persisted toggles + throttle state for proactive notifications.
// `isGroceryAlertsEnabled` gates the GPS arrival monitor in the Profile
// settings UI; `lastFiredByStore` lets the monitor cap notifications at
// one per store per cooldown window so we don't spam the user when they
// linger in the same Trader Joe's parking lot. UserDefaults is
// thread-safe so this stays nonisolated — the location manager's visit
// callback (background thread) and the Profile toggle (main thread)
// both read/write it directly.
@Observable
final class NotificationPrefs: @unchecked Sendable {
    static let shared = NotificationPrefs()

    private let defaults = UserDefaults.standard
    private let toggleKey = "notif.groceryAlerts.enabled"
    private let throttleKey = "notif.groceryAlerts.lastFired"
    private let expirationKey = "notif.expirationAlerts.enabled"

    // Don't fire two arrival notifications for the same store within this
    // window. 12h is long enough to cover a normal weekly-shop cadence
    // without missing a real second visit later in the day.
    private let cooldown: TimeInterval = 12 * 60 * 60

    private(set) var isGroceryAlertsEnabled: Bool
    private(set) var isExpirationAlertsEnabled: Bool

    init() {
        self.isGroceryAlertsEnabled = defaults.bool(forKey: toggleKey)
        // Default ON the first time we see this key — pantry expiration
        // is a headline feature, not opt-in. Once explicitly written,
        // honor that choice.
        if defaults.object(forKey: expirationKey) == nil {
            defaults.set(true, forKey: expirationKey)
            self.isExpirationAlertsEnabled = true
        } else {
            self.isExpirationAlertsEnabled = defaults.bool(forKey: expirationKey)
        }
    }

    func setGroceryAlertsEnabled(_ enabled: Bool) {
        isGroceryAlertsEnabled = enabled
        defaults.set(enabled, forKey: toggleKey)
    }

    func setExpirationAlertsEnabled(_ enabled: Bool) {
        isExpirationAlertsEnabled = enabled
        defaults.set(enabled, forKey: expirationKey)
    }

    // Returns true if we've never notified this store, or the cooldown
    // has elapsed since the last notification.
    func shouldFire(for storeKey: String, now: Date = .now) -> Bool {
        let map = defaults.dictionary(forKey: throttleKey) as? [String: TimeInterval] ?? [:]
        guard let last = map[storeKey] else { return true }
        return now.timeIntervalSince1970 - last >= cooldown
    }

    func recordFired(for storeKey: String, now: Date = .now) {
        var map = defaults.dictionary(forKey: throttleKey) as? [String: TimeInterval] ?? [:]
        map[storeKey] = now.timeIntervalSince1970
        defaults.set(map, forKey: throttleKey)
    }
}
