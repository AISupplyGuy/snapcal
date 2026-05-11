import Foundation
import Observation

#if canImport(HealthKit)
import HealthKit
#endif

// Single point of contact with Apple Health. Wraps:
//   • Read body mass (weight history) and observe live updates
//   • Write body mass when the user logs a weight in SnapCal
//   • Write dietary energy + protein/carbs/fat when a meal commits
//   • Read active energy burned (Apple Watch / iPhone) per day for the
//     net-calorie correlation in Insights
//
// The whole thing is wrapped in `#if canImport(HealthKit)` so the project
// continues to build on platforms (or future SDK changes) where HealthKit
// is unavailable. Free tier: weight read/write only. Active energy +
// projection is a Pro upsell surfaced from Insights.
//
// XCODE SETUP (one-time):
//   1. Project → Signing & Capabilities → + Capability → HealthKit
//   2. The default scope set is fine; SnapCal does not need clinical records.
//   3. Build & run on a real device — Simulator's HealthKit is read-only
//      and won't fire the permission sheet.
@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    enum AuthState: Equatable {
        case unknown
        case unavailable      // device doesn't support HealthKit (iPad pre-iOS 18, etc.)
        case denied
        case granted
    }

    private(set) var authState: AuthState = .unknown
    private(set) var lastImportedWeightKg: Double?
    private(set) var lastActiveEnergyKcal: Double?

    #if canImport(HealthKit)
    private let store = HKHealthStore()

    // Quantity types we read or write. Computed lazily so test rigs that
    // don't have HealthKit available don't crash on init.
    private var weightType:        HKQuantityType { HKQuantityType(.bodyMass) }
    private var dietaryEnergyType: HKQuantityType { HKQuantityType(.dietaryEnergyConsumed) }
    private var proteinType:       HKQuantityType { HKQuantityType(.dietaryProtein) }
    private var carbsType:         HKQuantityType { HKQuantityType(.dietaryCarbohydrates) }
    private var fatType:           HKQuantityType { HKQuantityType(.dietaryFatTotal) }
    private var activeEnergyType:  HKQuantityType { HKQuantityType(.activeEnergyBurned) }

    private var observerQuery: HKObserverQuery?
    #endif

    private init() {
        #if canImport(HealthKit)
        if !HKHealthStore.isHealthDataAvailable() {
            authState = .unavailable
        }
        #else
        authState = .unavailable
        #endif
    }

    // MARK: Permission

    var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    // Requests the full union of read + write scopes in one prompt.
    // HealthKit explicitly does NOT report on read-permission status (Apple
    // privacy: the OS lies to apps that try to detect denied reads), so
    // we treat any successful return as "granted" and let the actual data
    // queries reveal whether the user denied a specific scope.
    func requestAuthorization() async -> AuthState {
        #if canImport(HealthKit)
        guard isAvailable else {
            authState = .unavailable
            return .unavailable
        }
        let toShare: Set<HKSampleType> = [
            weightType, dietaryEnergyType, proteinType, carbsType, fatType
        ]
        let toRead: Set<HKObjectType> = [
            weightType, activeEnergyType, dietaryEnergyType
        ]
        do {
            try await store.requestAuthorization(toShare: toShare, read: toRead)
            authState = .granted
            startObservingWeight()
            return .granted
        } catch {
            #if DEBUG
            print("[HealthKit] requestAuthorization failed: \(error.localizedDescription)")
            #endif
            authState = .denied
            return .denied
        }
        #else
        authState = .unavailable
        return .unavailable
        #endif
    }

    // Lighter-weight check used at app launch to decide whether to wire up
    // observers without re-prompting. HealthKit only surfaces share status
    // truthfully; assume read worked if any scope was authorized for share.
    func refreshAuthState() {
        #if canImport(HealthKit)
        guard isAvailable else { authState = .unavailable; return }
        let status = store.authorizationStatus(for: weightType)
        switch status {
        case .sharingAuthorized: authState = .granted
        case .sharingDenied:     authState = .denied
        case .notDetermined:     authState = .unknown
        @unknown default:        authState = .unknown
        }
        if authState == .granted { startObservingWeight() }
        #endif
    }

    // MARK: Weight (read)

    // Returns up to `limit` most-recent weight samples in chronological
    // order. Uses a predicate-free query so observed updates always have
    // the freshest dataset to merge against.
    func recentWeights(limit: Int = 365) async -> [WeightEntry] {
        #if canImport(HealthKit)
        guard isAvailable else { return [] }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let entries: [WeightEntry] = (samples as? [HKQuantitySample] ?? [])
                    .map { sample in
                        let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                        return WeightEntry(
                            id: sample.uuid,
                            measuredAt: sample.endDate,
                            kilograms: kg,
                            note: sample.metadata?["note"] as? String
                        )
                    }
                    .sorted(by: { $0.measuredAt < $1.measuredAt })
                continuation.resume(returning: entries)
            }
            store.execute(query)
        }
        #else
        return []
        #endif
    }

    // Live observer: any time HealthKit reports a new weight sample
    // (logged from the Health app, an Apple Watch scale shortcut, or a
    // 3rd-party scale), pull it into our local cache so the Insights
    // chart updates without a tab refresh.
    private func startObservingWeight() {
        #if canImport(HealthKit)
        guard observerQuery == nil else { return }
        let q = HKObserverQuery(sampleType: weightType, predicate: nil) { [weak self] _, _, _ in
            Task { @MainActor in
                let latest = await self?.recentWeights(limit: 1).last
                self?.lastImportedWeightKg = latest?.kilograms
            }
        }
        observerQuery = q
        store.execute(q)
        store.enableBackgroundDelivery(for: weightType, frequency: .immediate) { _, _ in }
        #endif
    }

    // MARK: Weight (write)

    // Mirrors a SnapCal-logged weight into Apple Health so users who
    // also use the Health app see one consistent timeline. UUID-tagged
    // metadata lets us avoid double-importing our own writes.
    func writeWeight(kilograms: Double, at date: Date = .now, note: String? = nil) async {
        #if canImport(HealthKit)
        guard authState == .granted else { return }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms)
        var metadata: [String: Any] = ["source": "SnapCal"]
        if let note { metadata["note"] = note }
        let sample = HKQuantitySample(
            type: weightType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: metadata
        )
        do {
            try await store.save(sample)
        } catch {
            #if DEBUG
            print("[HealthKit] writeWeight failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    // MARK: Meal nutrition (write)

    // Writes a single meal's totals as four separate HK samples (energy,
    // protein, carbs, fat) so they land in the right Apple Health rows.
    // Skipped when authState != granted so we don't spam Console with
    // permission errors during development.
    func writeMeal(
        calories: Double,
        proteinGrams: Double,
        carbGrams: Double,
        fatGrams: Double,
        at date: Date = .now,
        mealId: UUID? = nil
    ) async {
        #if canImport(HealthKit)
        guard authState == .granted else { return }
        var metadata: [String: Any] = ["source": "SnapCal"]
        if let mealId { metadata["mealId"] = mealId.uuidString }

        let samples: [HKQuantitySample] = [
            HKQuantitySample(
                type: dietaryEnergyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: date, end: date, metadata: metadata
            ),
            HKQuantitySample(
                type: proteinType,
                quantity: HKQuantity(unit: .gram(), doubleValue: proteinGrams),
                start: date, end: date, metadata: metadata
            ),
            HKQuantitySample(
                type: carbsType,
                quantity: HKQuantity(unit: .gram(), doubleValue: carbGrams),
                start: date, end: date, metadata: metadata
            ),
            HKQuantitySample(
                type: fatType,
                quantity: HKQuantity(unit: .gram(), doubleValue: fatGrams),
                start: date, end: date, metadata: metadata
            ),
        ]
        do {
            try await store.save(samples)
        } catch {
            #if DEBUG
            print("[HealthKit] writeMeal failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    // MARK: Active energy (read)

    // Returns daily totals of active energy burned for the last `days`
    // days, oldest-first. Powers the net-calorie correlation card in
    // Insights — users who actually wear a Watch get a closed-loop
    // calories-in-vs-out story without us having to nag them about it.
    func dailyActiveEnergy(days: Int = 30) async -> [(date: Date, kcal: Double)] {
        #if canImport(HealthKit)
        guard isAvailable, authState == .granted else { return [] }
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: .now).addingTimeInterval(86_400)
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return [] }

        return await withCheckedContinuation { continuation in
            var interval = DateComponents()
            interval.day = 1
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let q = HKStatisticsCollectionQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, results, _ in
                var out: [(Date, Double)] = []
                results?.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                    let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    out.append((stats.startDate, kcal))
                }
                continuation.resume(returning: out)
            }
            store.execute(q)
        }
        #else
        return []
        #endif
    }
}
