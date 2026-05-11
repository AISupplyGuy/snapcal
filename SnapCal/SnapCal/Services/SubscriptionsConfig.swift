import Foundation

// Constants the Subscriptions service reads at launch. Live in their own
// file so the API key swap is a single, obvious edit.
//
// SETUP (one-time)
// 1. Sign in at https://app.revenuecat.com.
// 2. New project → add an iOS app → tie it to your App Store Connect bundle.
// 3. Create a StoreKit subscription product in App Store Connect:
//      - Product ID:  snapcal.pro.monthly   ($4.99/mo recommended)
//      - Product ID:  snapcal.pro.annual    ($29.99/yr recommended, ~50% discount)
//    Add a 7-day free trial as an introductory offer on both.
// 4. Back in RevenueCat:
//      - Entitlements → create entitlement id "pro"
//      - Products → import both subscriptions, attach to "pro" entitlement
//      - Offerings → create "default" offering with $rc_monthly and $rc_annual packages
// 5. Project → API keys → "Public app-specific API keys" → iOS → copy.
//    Paste into `publicApiKey` below. The PUBLIC key is safe to commit;
//    the SECRET key is not.
//
// FREE-TIER POLICY (enforced by UsageMeter)
//   • 3 photo meal scans per day
//   • 1 barcode scan per day
//   • Grocery arrival alerts: Pro-only
//   • Weight projections in Insights: Pro-only
//   • Cook recipe generations: 1/day free, unlimited Pro
enum SubscriptionsConfig {
    static let publicApiKey = "appl_CWiCdBZdfkQTmYaRKatXPovyOwQ"
    static let entitlementId = "pro"

    static var isConfigured: Bool {
        !publicApiKey.isEmpty
    }
}
