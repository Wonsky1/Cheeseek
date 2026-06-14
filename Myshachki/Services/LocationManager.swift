import Combine
import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let maxAcceptedHorizontalAccuracy: CLLocationAccuracy = 50
    static let preferredQualityAccuracy: CLLocationAccuracy = 30
    static let minimumMovementDistance: CLLocationDistance = 3

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var latestAccuracy: CLLocationAccuracy?
    @Published private(set) var statusText: String
    @Published private(set) var isSimulating = false

    private let manager: CLLocationManager
    private var locationUpdateHandler: ((CLLocation) -> Void)?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        self.latestLocation = manager.location
        self.latestAccuracy = manager.location?.horizontalAccuracy
        self.statusText = manager.location == nil ? "Location not started" : "Location ready"
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
        self.manager.distanceFilter = 1
        self.manager.activityType = .fitness
        self.manager.pausesLocationUpdatesAutomatically = false
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func requestCurrentLocation() {
        guard !isSimulating else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func startUpdates(allowsBackground: Bool = false) {
        statusText = "Tracking live"
        guard !isSimulating else {
            statusText = "Admin simulator"
            return
        }
        manager.allowsBackgroundLocationUpdates = allowsBackground
        manager.showsBackgroundLocationIndicator = allowsBackground
        manager.startUpdatingLocation()
    }

    func setLocationUpdateHandler(_ handler: @escaping (CLLocation) -> Void) {
        locationUpdateHandler = handler
    }

    func stopUpdates() {
        statusText = "Tracking paused"
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        statusText = switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: "Location ready"
        case .denied, .restricted: "Location denied"
        case .notDetermined: "Location permission needed"
        @unknown default: "Location unavailable"
        }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            requestCurrentLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isSimulating else { return }
        guard let location = locations.last else { return }
        latestLocation = location
        latestAccuracy = location.horizontalAccuracy
        statusText = location.horizontalAccuracy <= Self.preferredQualityAccuracy ? "GPS solid" : "GPS settling"
        locationUpdateHandler?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        statusText = error.localizedDescription
    }

    func enableSimulation(at coordinate: CLLocationCoordinate2D) {
        authorizationStatus = .authorizedWhenInUse
        isSimulating = true
        pushSimulatedLocation(coordinate)
        statusText = "Admin simulator"
    }

    func stepSimulation(latitudeDelta: Double, longitudeDelta: Double) {
        let baseCoordinate = latestLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
        let coordinate = CLLocationCoordinate2D(
            latitude: baseCoordinate.latitude + latitudeDelta,
            longitude: baseCoordinate.longitude + longitudeDelta
        )
        pushSimulatedLocation(coordinate)
        statusText = "Admin simulator"
    }

    func resetSimulation(at coordinate: CLLocationCoordinate2D) {
        isSimulating = true
        pushSimulatedLocation(coordinate)
        statusText = "Admin simulator reset"
    }

    private func pushSimulatedLocation(_ coordinate: CLLocationCoordinate2D) {
        latestLocation = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: -1,
            timestamp: .now
        )
        latestAccuracy = 5
        if let latestLocation {
            locationUpdateHandler?(latestLocation)
        }
    }
}

extension LocationManager {
    static var preview: LocationManager {
        let manager = LocationManager()
        manager.latestLocation = CLLocation(latitude: 52.2297, longitude: 21.0122)
        manager.latestAccuracy = 8
        manager.statusText = "Preview GPS"
        return manager
    }
}
