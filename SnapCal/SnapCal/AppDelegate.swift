import UIKit
import UserNotifications

// Hooks into the UIKit lifecycle so we can:
//   1. Configure RevenueCat at launch (must happen before any view tries
//      to read Subscriptions.shared.isPro).
//   2. Re-attach the GroceryArrivalMonitor — visits get delivered into a
//      freshly relaunched process when a user is detected at a place,
//      so we have to start monitoring from didFinishLaunching, not just
//      from the toggle in Profile.
//   3. Be the UNUserNotificationCenter delegate so taps on the
//      grocery-arrival notification deep-link into the Pantry tab via
//      NotificationRouter.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        GroceryNotifications.registerCategory()

        Task { @MainActor in
            Subscriptions.shared.configure()
            GroceryArrivalMonitor.shared.startIfEnabled()
            // Re-schedule pantry expiration notifications on every launch
            // — covers items that became "due in 3 days" while the app
            // was closed without us needing a BGTaskScheduler entry.
            ExpirationNotificationScheduler.shared.scheduleAll(for: PantryStore.shared.items)
            HealthKitService.shared.refreshAuthState()
            // Best-effort one-shot import on cold launch — pulls weights
            // logged elsewhere into the local cache so Insights renders
            // the full history without waiting for the observer to fire.
            if HealthKitService.shared.authState == .granted {
                let imported = await HealthKitService.shared.recentWeights()
                WeightLog.shared.ingestFromHealth(imported)
            }
        }
        return true
    }

    // Show the banner even when the app is in the foreground — otherwise
    // the user has no idea we noticed they walked into the store.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let destination = response.notification.request.content.userInfo["destination"] as? String
        await MainActor.run {
            switch destination {
            case "scan-receipt":
                NotificationRouter.shared.requestScanReceipt()
            case "pantry":
                NotificationRouter.shared.requestPantry()
            default:
                break
            }
        }
    }
}
