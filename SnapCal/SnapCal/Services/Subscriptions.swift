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

    private(set) var isPro: Bool = false
    private(set) var isReady: Bool = false

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
            self.isPro = info.entitlements[SubscriptionsConfig.entitlementId]?.isActive ?? false
            self.currentOffering = try? await Purchases.shared.offerings().current
            self.isReady = true
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
            self.isPro = info.entitlements[SubscriptionsConfig.entitlementId]?.isActive ?? false
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
            self.isPro = active
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
