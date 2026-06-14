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
    private let newBuildingCount: Int
    private let emptyFeatureCollection = #"{"type":"FeatureCollection","features":[]}"#

    init(session: WalkSession, backendSyncService: BackendSyncServing, walkSessionStore: WalkSessionStoring) {
        self.session = session
        self.backendSyncService = backendSyncService
        self.walkSessionStore = walkSessionStore
        self.syncStatusText = session.syncStatus.label
        self.newBuildingCount = CoverageBuildingCodec.buildingIDs(
            from: CoverageBuildingCodec.sideIDs(from: session.points)
        ).count
    }

    var canSyncToServer: Bool {
        !isSavingToServer && syncStatusText != SyncStatus.synced.label
    }

    var newStreetsText: String {
        "\(newBuildingCount) buildings"
    }

    var newAreaText: String {
        session.distanceMeters.formattedDistance
    }

    var mapCenterCoordinate: CLLocationCoordinate2D {
        session.points.last?.coordinate ?? CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
    }

    var mapStorageKey: String {
        session.userId
    }

    var routeGeoJSON: String {
        guard session.points.count > 1 else { return emptyFeatureCollection }
        let routeStatus = syncStatusText == SyncStatus.synced.label ? "explored" : "active"
        return jsonString([
            "type": "FeatureCollection",
            "features": [[
                "type": "Feature",
                "properties": [
                    "status": routeStatus
                ],
                "geometry": [
                    "type": "LineString",
                    "coordinates": session.points.map { [$0.longitude, $0.latitude] }
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
}
