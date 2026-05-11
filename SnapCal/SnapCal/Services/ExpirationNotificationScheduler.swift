import Foundation
import UserNotifications

// Schedules local notifications for pantry items that are about to expire
// or have just expired. Two flavors:
//
//   • Per-item warning at 3 days, 1 day, and day-of expiration. Fires at
//     9 AM local time on the relevant date. Cancelled and re-scheduled
//     whenever Pantry changes so a "use it tomorrow" item that gets
//     deleted today doesn't fire stale.
//
//   • A daily 8:30 AM "use these today" digest when anything expires
//     within 24h — capped at one notification with a count, so the user
//     never sees five pings on a Sunday morning.
//
// Designed to be a no-op when the user hasn't enabled pantry alerts in
// Profile, and to fail silently when notification authorization isn't
// granted. Live alongside GroceryNotifications so the two paths share
// the UNUserNotificationCenter delegate registered in AppDelegate.
@MainActor
final class ExpirationNotificationScheduler {
    static let shared = ExpirationNotificationScheduler()

    private static let identifierPrefix = "snapcal.pantry.expiration."
    private static let digestIdentifier = "snapcal.pantry.expiration.digest"

    private init() {}

    // MARK: Public API

    // Cancels every previously-scheduled pantry notification and rebuilds
    // the schedule from `items`. Idempotent — safe to call from add /
    // update / delete in PantryStore and from app foreground.
    func scheduleAll(for items: [PantryItem]) {
        Task {
            await reschedule(items: items)
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: Internals

    private func reschedule(items: [PantryItem]) async {
        let center = UNUserNotificationCenter.current()
        // Cancel everything we own, then re-issue. Cheaper than diffing
        // for the pantry sizes we expect (a few dozen items max).
        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) || $0 == Self.digestIdentifier }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        // Gate behind the user pref + system permission.
        guard NotificationPrefs.shared.isExpirationAlertsEnabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        var hasItemsExpiringToday = false
        var digestNames: [String] = []

        for item in items {
            guard let expiration = item.expirationDate else { continue }
            for offset in [3, 1, 0] {
                guard let fire = fireDate(forItemExpiring: expiration, daysBefore: offset) else { continue }
                guard fire > .now else { continue }
                if offset == 0 { hasItemsExpiringToday = true }
                let title: String
                let body: String
                switch offset {
                case 3:
                    title = "Use \(item.name) soon"
                    body = "Expires in 3 days. Cook tab can build a recipe around it."
                case 1:
                    title = "\(item.name) expires tomorrow"
                    body = "Tap to find a recipe that fits today's macros."
                default:
                    title = "\(item.name) expires today"
                    body = "Last call — Cook can use it in a quick recipe."
                }
                let id = identifier(for: item, daysBefore: offset)
                if offset == 0 { digestNames.append(item.name) }
                await schedule(
                    id: id, title: title, body: body, fireDate: fire,
                    destination: "pantry"
                )
            }

            // "Expired" follow-up the day after — gentle reminder to
            // delete or restock without nagging on the actual day.
            if let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: expiration),
               let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay),
               fire > .now {
                let id = identifier(for: item, suffix: "expired")
                await schedule(
                    id: id,
                    title: "\(item.name) expired",
                    body: "Toss it or restock — keeps Cook's suggestions accurate.",
                    fireDate: fire,
                    destination: "pantry"
                )
            }
        }

        // Daily digest: if anything is expiring today, fire one summary
        // notification at 8:30 AM so the user wakes up to "you've got 3
        // things to use today" instead of three separate pings at 9.
        if hasItemsExpiringToday, !digestNames.isEmpty,
           let fire = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: .now),
           fire > .now {
            let preview = digestNames.prefix(3).joined(separator: ", ")
            let extra = max(0, digestNames.count - 3)
            let summary = extra > 0 ? "\(preview) +\(extra) more" : preview
            await schedule(
                id: Self.digestIdentifier,
                title: digestNames.count == 1 ? "Use it today" : "\(digestNames.count) things to use today",
                body: summary,
                fireDate: fire,
                destination: "pantry"
            )
        }
    }

    private func schedule(
        id: String,
        title: String,
        body: String,
        fireDate: Date,
        destination: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["destination": destination]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            #if DEBUG
            print("[ExpirationScheduler] add failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func identifier(for item: PantryItem, daysBefore: Int) -> String {
        "\(Self.identifierPrefix)\(item.id.uuidString).d\(daysBefore)"
    }

    private func identifier(for item: PantryItem, suffix: String) -> String {
        "\(Self.identifierPrefix)\(item.id.uuidString).\(suffix)"
    }

    // 9 AM local on the morning that's `daysBefore` ahead of the
    // expiration date. nil if the expiration is in the past for that
    // window.
    private func fireDate(forItemExpiring expiration: Date, daysBefore: Int) -> Date? {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: -daysBefore, to: expiration) else { return nil }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)
    }
}
