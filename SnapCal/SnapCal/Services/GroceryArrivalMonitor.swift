import CoreLocation
import Foundation
import MapKit
import UserNotifications

// Background-aware arrival detector: when the OS reports that the user
// has visited a place, we ask MapKit whether anything within 75 m of
// that coordinate is a grocery store / supermarket. If so, we schedule
// the "don't forget to scan your receipt" local notification (subject
// to the 12 h-per-store throttle in NotificationPrefs).
//
// `startMonitoringVisits` is the cheapest way to hear about real
// arrivals — the OS only wakes us when it has high confidence the
// user has stopped somewhere meaningful, so we don't burn battery
// polling GPS.
@MainActor
final class GroceryArrivalMonitor: NSObject, CLLocationManagerDelegate {
    static let shared = GroceryArrivalMonitor()

    private let manager = CLLocationManager()
    private var isStarted = false

    // Categories MapKit will surface for "this place sells groceries."
    private static let groceryCategories: Set<MKPointOfInterestCategory> = {
        var set: Set<MKPointOfInterestCategory> = [.foodMarket]
        // Convenience-store POI category is iOS 18+. Build it via rawValue
        // so this still compiles against the iOS 17 SDK; on older OSes
        // MapKit just won't return matches for that raw value.
        if #available(iOS 18.0, *) {
            set.insert(MKPointOfInterestCategory(rawValue: "MKPOICategoryConvenienceStore"))
        }
        return set
    }()

    // Max distance from the visit centroid to a candidate POI for it to
    // count as the place the user actually walked into.
    private static let matchRadiusMeters: CLLocationDistance = 75

    override init() {
        super.init()
        manager.delegate = self
    }

    // MARK: Lifecycle

    // Idempotent. Called from SnapCalApp on launch when the user has
    // already enabled grocery alerts; called from the Profile toggle
    // when they flip it on.
    func startIfEnabled() {
        guard NotificationPrefs.shared.isGroceryAlertsEnabled else {
            stop()
            return
        }
        guard !isStarted else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.startMonitoringVisits()
            isStarted = true
        case .authorizedWhenInUse, .notDetermined, .restricted, .denied:
            // Caller is expected to have nudged the user through the
            // permission ladder. We start as soon as Always is granted
            // via the delegate callback below.
            break
        @unknown default:
            break
        }
    }

    func stop() {
        guard isStarted else { return }
        manager.stopMonitoringVisits()
        isStarted = false
    }

    // Permission ladder: "When In Use" first (less scary), then "Always"
    // once the user has actually opted in to the feature.
    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            startIfEnabled()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            startIfEnabled()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // Skip departures (departureDate finite) — we only care about
        // arrivals. CLVisit signals an arrival when departureDate is in
        // the distant future.
        guard visit.departureDate == .distantFuture else { return }
        let coordinate = visit.coordinate
        Task { @MainActor in
            await self.handleArrival(at: coordinate)
        }
    }

    // MARK: Resolution

    private func handleArrival(at coordinate: CLLocationCoordinate2D) async {
        guard let store = await nearestGroceryStore(near: coordinate) else { return }
        let key = storeKey(name: store.name ?? "store", coordinate: store.placemark.coordinate)
        guard NotificationPrefs.shared.shouldFire(for: key) else { return }
        await GroceryNotifications.scheduleArrival(storeName: store.name ?? "the grocery store")
        NotificationPrefs.shared.recordFired(for: key)
    }

    private func nearestGroceryStore(near coordinate: CLLocationCoordinate2D) async -> MKMapItem? {
        let request = MKLocalPointsOfInterestRequest(
            center: coordinate,
            radius: 200
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: Array(Self.groceryCategories))
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            let visitLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return response.mapItems
                .map { item -> (MKMapItem, CLLocationDistance) in
                    let loc = CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    )
                    return (item, loc.distance(from: visitLocation))
                }
                .filter { $0.1 <= Self.matchRadiusMeters }
                .min(by: { $0.1 < $1.1 })?
                .0
        } catch {
            #if DEBUG
            print("[GroceryArrivalMonitor] MKLocalSearch failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // Stable per-store identifier for throttling. Coordinates are rounded
    // so a parking-lot drift between visits doesn't defeat the cooldown.
    private func storeKey(name: String, coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude * 1000).rounded() / 1000
        let lon = (coordinate.longitude * 1000).rounded() / 1000
        return "\(name.lowercased())@\(lat),\(lon)"
    }
}
