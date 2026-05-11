import Foundation
import Observation
import SwiftUI

#if canImport(RevenueCat)
import RevenueCat
#endif

// Single source of truth for the user's Pro entitlement. Wraps RevenueCat
// when the SPM package is present, otherwise falls back to a free-tier
// stub so the project compiles before the package has been added.
//
// Add the RevenueCat package via Xcode:
//   File → Add Package Dependencies →
//   https://github.com/RevenueCat/purchases-ios-spm.git
//   (product: RevenueCat)
@MainActor
@Observable
final class Subscriptions {
    static let shared = Subscriptions()

    // Backing storage from RevenueCat. The public `isPro` accessor below
    // ORs this with the debug override so a developer-toggled override
    // wins regardless of what RevenueCat reports.
    private(set) var isProFromStore: Bool = false
    private(set) var isReady: Bool = false

    #if DEBUG
    // Persisted override so a flip survives relaunches during dev/demo.
    // Read/written by the Pro override row in Profile (DEBUG-only build).
    var debugProOverride: Bool {
        get { UserDefaults.standard.bool(forKey: "debug.proOverride") }
        set { UserDefaults.standard.set(newValue, forKey: "debug.proOverride") }
    }
    #endif

    var isPro: Bool {
        #if DEBUG
        if debugProOverride { return true }
        #endif
        return isProFromStore
    }

    // Last value of appUserID seen — exposes the RevenueCat-generated
    // anonymous ID (`$RCAnonymousID:…`) so a debug surface can show it
    // and you can paste it into the dashboard to grant entitlements.
    private(set) var currentAppUserID: String?

    #if canImport(RevenueCat)
    private(set) var currentOffering: Offering?
    #endif

    private init() {}

    // Called once at app launch. Safe to call when the package isn't
    // installed (becomes a no-op) or when the API key hasn't been pasted
    // yet (logs a warning and stays in free-tier).
    func configure() {
        #if canImport(RevenueCat)
        guard SubscriptionsConfig.isConfigured else {
            #if DEBUG
            print("[Subscriptions] No API key in SubscriptionsConfig — staying free-tier.")
            #endif
            return
        }
        Purchases.logLevel = .info
        Purchases.configure(withAPIKey: SubscriptionsConfig.publicApiKey)
        Task { await refresh() }
        #else
        #if DEBUG
        print("[Subscriptions] RevenueCat SPM not installed — staying free-tier.")
        #endif
        #endif
    }

    func refresh() async {
        #if canImport(RevenueCat)
        do {
            let info = try await Purchases.shared.customerInfo()
            self.isProFromStore = info.entitlements[SubscriptionsConfig.entitlementId]?.isActive ?? false
            self.currentOffering = try? await Purchases.shared.offerings().current
            self.currentAppUserID = Purchases.shared.appUserID
            self.isReady = true
            #if DEBUG
            print("[Subscriptions] appUserID = \(Purchases.shared.appUserID)")
            #endif
        } catch {
            #if DEBUG
            print("[Subscriptions] refresh failed: \(error.localizedDescription)")
            #endif
        }
        #else
        self.isReady = true
        #endif
    }

    func restore() async {
        #if canImport(RevenueCat)
        do {
            let info = try await Purchases.shared.restorePurchases()
            self.isProFromStore = info.entitlements[SubscriptionsConfig.entitlementId]?.isActive ?? false
        } catch {
            #if DEBUG
            print("[Subscriptions] restore failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    #if canImport(RevenueCat)
    func purchase(_ package: Package) async -> PurchaseOutcome {
        do {
            let result = try await Purchases.shared.purchase(package: package)
            let active = result.customerInfo.entitlements[SubscriptionsConfig.entitlementId]?.isActive ?? false
            self.isProFromStore = active
            if result.userCancelled { return .cancelled }
            return active ? .purchased : .pending
        } catch {
            return .failed(error.localizedDescription)
        }
    }
    #endif
}

enum PurchaseOutcome {
    case purchased
    case pending
    case cancelled
    case failed(String)
}
