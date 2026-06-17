import Combine
import CoreLocation
import Foundation

@MainActor
final class WalkSummaryViewModel: ObservableObject {
    @Published private(set) var syncStatusText: String
    @Published private(set) var isSavingToServer = false
    @Published private(set) var errorMessage: String?

    @Published private(set) var session: WalkSession
    private let backendSyncService: BackendSyncServing
    private let walkSessionStore: WalkSessionStoring
    let mapPerspectiveMode: MapPerspectiveMode
    let mapStyleMode: MapStyleMode
    let summaryCoverageGeoJSON: String
    private let newBuildingCount: Int
    let emptyFeatureCollection = #"{"type":"FeatureCollection","features":[]}"#

    init(
        session: WalkSession,
        backendSyncService: BackendSyncServing,
        walkSessionStore: WalkSessionStoring,
        mapPerspectiveMode: MapPerspectiveMode,
        mapStyleMode: MapStyleMode,
        summaryCoverageGeoJSON: String = #"{"type":"FeatureCollection","features":[]}"#
    ) {
        self.session = session
        self.backendSyncService = backendSyncService
        self.walkSessionStore = walkSessionStore
        self.mapPerspectiveMode = mapPerspectiveMode
        self.mapStyleMode = mapStyleMode
        self.summaryCoverageGeoJSON = summaryCoverageGeoJSON
        self.syncStatusText = session.syncStatus.label
        let capturedFeatureCount = Self.activeFeatureCount(in: summaryCoverageGeoJSON)
        self.newBuildingCount = capturedFeatureCount > 0
            ? capturedFeatureCount
            : CoverageBuildingCodec.buildingIDs(
                from: CoverageBuildingCodec.sideIDs(from: session.points)
            ).count
    }

    var canSyncToServer: Bool {
        !isSavingToServer && syncStatusText != SyncStatus.synced.label
    }

    var newStreetsText: String {
        "\(newBuildingCount) buildings"
    }

    var paceText: String {
        guard session.distanceMeters > 0, session.durationSeconds > 0 else { return "Not enough data" }
        let secondsPerKilometer = session.durationSeconds / (session.distanceMeters / 1000)
        return secondsPerKilometer.formattedPace
    }

    var mapCenterCoordinate: CLLocationCoordinate2D {
        guard !session.points.isEmpty else {
            return CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
        }
        let latitudes = session.points.map(\.latitude)
        let longitudes = session.points.map(\.longitude)
        return CLLocationCoordinate2D(
            latitude: ((latitudes.min() ?? 52.2297) + (latitudes.max() ?? 52.2297)) / 2,
            longitude: ((longitudes.min() ?? 21.0122) + (longitudes.max() ?? 21.0122)) / 2
        )
    }

    var mapStorageKey: String {
        session.userId
    }

    var routeCoordinates: [CLLocationCoordinate2D] {
        session.points.map(\.coordinate)
    }

    var routeGeoJSON: String {
        guard session.points.count > 1 else { return emptyFeatureCollection }
        return jsonString([
            "type": "FeatureCollection",
            "features": [[
                "type": "Feature",
                "properties": [
                    "status": "summary"
                ],
                "geometry": [
                    "type": "LineString",
                    "coordinates": interpolatedRouteCoordinates(from: session.points).map { [$0.longitude, $0.latitude] }
                ]
            ]]
        ])
    }

    func syncToServer() async {
        guard canSyncToServer else { return }
        isSavingToServer = true
        errorMessage = nil
        defer { isSavingToServer = false }
        do {
            try await backendSyncService.syncWalkSession(session)
            session.syncStatus = .synced
            try await walkSessionStore.saveSession(session)
            syncStatusText = SyncStatus.synced.label
        } catch {
            session.syncStatus = .failed
            try? await walkSessionStore.saveSession(session)
            syncStatusText = SyncStatus.failed.label
            errorMessage = error.localizedDescription
        }
    }

    private func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return emptyFeatureCollection
        }
        return string
    }

    private func interpolatedRouteCoordinates(from points: [TrackPoint]) -> [CLLocationCoordinate2D] {
        guard let first = points.first?.coordinate else { return [] }
        var coordinates = [first]
        for pair in zip(points, points.dropFirst()) {
            let start = pair.0.coordinate
            let end = pair.1.coordinate
            let distance = pair.0.location.distance(from: pair.1.location)
            let stepCount = max(1, Int(ceil(distance / 2.0)))
            for step in 1...stepCount {
                let progress = Double(step) / Double(stepCount)
                coordinates.append(CLLocationCoordinate2D(
                    latitude: start.latitude + ((end.latitude - start.latitude) * progress),
                    longitude: start.longitude + ((end.longitude - start.longitude) * progress)
                ))
                if coordinates.count >= 700 {
                    return coordinates
                }
            }
        }
        return coordinates
    }

    private static func activeFeatureCount(in geoJSON: String) -> Int {
        guard
            let data = geoJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = object["features"] as? [[String: Any]]
        else {
            return 0
        }
        return features.filter { feature in
            guard
                let properties = feature["properties"] as? [String: Any],
                let status = properties["status"] as? String
            else {
                return false
            }
            return status != "explored"
        }.count
    }
}
