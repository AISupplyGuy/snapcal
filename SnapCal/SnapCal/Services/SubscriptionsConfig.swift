import Foundation

// Constants the Subscriptions service reads at launch. Live in their own
// file so the API key swap is a single, obvious edit.
//
// SETUP
// 1. Sign in at https://app.revenuecat.com.
// 2. Create an iOS app project, attach a StoreKit subscription product to
//    an entitlement named "pro" (or change `entitlementId` below).
// 3. Copy your Public Apple API key (Project → API keys → "Public
//    app-specific API keys" → iOS) and paste it into `publicApiKey`.
//    The public key is safe to commit; the SECRET key is not.
enum SubscriptionsConfig {
    static let publicApiKey = ""
    static let entitlementId = "pro"

    static var isConfigured: Bool {
        !publicApiKey.isEmpty
    }
}
