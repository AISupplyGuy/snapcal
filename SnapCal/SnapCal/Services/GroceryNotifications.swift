import Foundation
import UserNotifications

// Local notification scheduler + tap routing for the grocery-arrival
// path. Kept separate from GroceryArrivalMonitor so the system delegate
// (registered on SnapCalApp's AppDelegate) can answer
// `userNotificationCenter:didReceive:` without dragging CoreLocation
// into the launch graph.
enum GroceryNotifications {
    static let categoryId = "snapcal.grocery.arrival"
    static let actionScan = "snapcal.grocery.action.scan"

    // Asks the OS for permission to post local notifications. Idempotent
    // — once the user has decided we just return their current setting.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted { registerCategory() }
                return granted
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    static func registerCategory() {
        let scan = UNNotificationAction(
            identifier: actionScan,
            title: "Open SnapCal",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [scan],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // Posts the arrival notification immediately. The body intentionally
    // hooks into the receipt-scan use case the user asked for, even
    // though receipt OCR isn't built yet — for now the tap deep-links
    // to the Pantry tab where they can add items manually, and we'll
    // swap the destination once OCR ships.
    static func scheduleArrival(storeName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "You're at \(storeName)"
        content.body = "Don't forget to scan your receipt."
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["destination": "scan-receipt"]

        // Trigger nil = deliver right now.
        let request = UNNotificationRequest(
            identifier: "grocery.arrival.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            #if DEBUG
            print("[GroceryNotifications] schedule failed: \(error.localizedDescription)")
            #endif
        }
    }
}

// Surface for SwiftUI to observe so we can route a notification tap to
// the right tab. The AppDelegate writes here when the user taps; views
// read it and navigate.
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    private init() {}

    // Bumped each time a tap arrives — observers compare against their
    // last-seen value and react. Using a counter (not a single nullable
    // payload) lets multiple observers each consume the event without
    // stepping on each other.
    private(set) var pantryRequestVersion = 0
    private(set) var scanReceiptRequestVersion = 0

    func requestPantry() {
        pantryRequestVersion &+= 1
    }

    func requestScanReceipt() {
        // PantryView observes this to open the receipt scanner; bump
        // pantryRequestVersion too so ContentView switches tabs in the
        // same routing call.
        scanReceiptRequestVersion &+= 1
        pantryRequestVersion &+= 1
    }
}
