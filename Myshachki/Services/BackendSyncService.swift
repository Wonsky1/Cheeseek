import CoreLocation
import Foundation

protocol BackendSyncServing {
    func syncWalkSession(_ session: WalkSession) async throws
    func fetchSharedProgress() async throws -> SharedProgress
    func uploadTrackPoints(sessionId: UUID, userId: UUID, points: [TrackPoint]) async throws
    func fetchCoverage(userId: UUID, areaId: String) async throws -> Set<String>
    func upsertCoverage(userId: UUID, areaId: String, coveredFeatureIDs: Set<String>) async throws -> Set<String>
    func fetchMapFeatures(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        coveredFeatureIDs: Set<String>,
        activeFeatureIDs: Set<String>
    ) async throws -> String
    func fetchMapCoverageCandidates(points: [TrackPoint]) async throws -> Set<String>
}

@MainActor
final class HTTPBackendSyncService: BackendSyncServing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func syncWalkSession(_ session: WalkSession) async throws {
        guard let userId = UUID(uuidString: session.userId) else { return }
        let request = WalkSessionCreateRequest(
            id: session.id,
            userId: userId,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            distanceMeters: session.distanceMeters,
            durationSeconds: session.durationSeconds,
            syncStatus: session.syncStatus.rawValue
        )
        let _: WalkSessionResponseDTO = try await apiClient.post("/walk-sessions", body: request)
        try await uploadTrackPoints(sessionId: session.id, userId: userId, points: session.points)
    }

    func fetchSharedProgress() async throws -> SharedProgress {
        do {
            return try await apiClient.get("/shared-progress")
        } catch {
            return .placeholder
        }
    }

    func uploadTrackPoints(sessionId: UUID, userId: UUID, points: [TrackPoint]) async throws {
        let request = TrackPointsUploadRequest(
            userId: userId,
            points: points.map {
                TrackPointDTO(
                    id: $0.id,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    altitude: $0.altitude,
                    horizontalAccuracy: $0.horizontalAccuracy,
                    timestamp: $0.timestamp
                )
            }
        )
        let _: TrackPointsUploadResponse = try await apiClient.post("/walk-sessions/\(sessionId.uuidString)/points", body: request)
    }

    func fetchCoverage(userId: UUID, areaId: String) async throws -> Set<String> {
        let response: CoverageResponseDTO = try await apiClient.get(
            "/coverage",
            queryItems: [
                URLQueryItem(name: "userId", value: userId.uuidString),
                URLQueryItem(name: "areaId", value: areaId)
            ]
        )
        return Set(response.coveredFeatureIds)
    }

    func upsertCoverage(userId: UUID, areaId: String, coveredFeatureIDs: Set<String>) async throws -> Set<String> {
        let request = CoverageUpsertRequestDTO(
            userId: userId,
            areaId: areaId,
            coveredFeatureIds: coveredFeatureIDs.sorted()
        )
        let response: CoverageResponseDTO = try await apiClient.put("/coverage", body: request)
        return Set(response.coveredFeatureIds)
    }

    func fetchMapFeatures(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        coveredFeatureIDs: Set<String>,
        activeFeatureIDs: Set<String>
    ) async throws -> String {
        try await apiClient.getRawString(
            "/map/features",
            queryItems: [
                URLQueryItem(name: "south", value: String(south)),
                URLQueryItem(name: "west", value: String(west)),
                URLQueryItem(name: "north", value: String(north)),
                URLQueryItem(name: "east", value: String(east)),
                URLQueryItem(name: "coveredFeatureIds", value: coveredFeatureIDs.sorted().joined(separator: ",")),
                URLQueryItem(name: "activeFeatureIds", value: activeFeatureIDs.sorted().joined(separator: ","))
            ]
        )
    }

    func fetchMapCoverageCandidates(points: [TrackPoint]) async throws -> Set<String> {
        let request = MapCoverageCandidatesRequestDTO(
            points: points.map {
                TrackPointDTO(
                    id: $0.id,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    altitude: $0.altitude,
                    horizontalAccuracy: $0.horizontalAccuracy,
                    timestamp: $0.timestamp
                )
            }
        )
        let response: MapCoverageCandidatesResponseDTO = try await apiClient.post("/map/coverage-candidates", body: request)
        return Set(response.coveredFeatureIds)
    }
}

@MainActor
final class MockBackendSyncService: BackendSyncServing {
    func syncWalkSession(_ session: WalkSession) async throws {}
    func fetchSharedProgress() async throws -> SharedProgress { .placeholder }
    func uploadTrackPoints(sessionId: UUID, userId: UUID, points: [TrackPoint]) async throws {}
    func fetchCoverage(userId: UUID, areaId: String) async throws -> Set<String> { [] }
    func upsertCoverage(userId: UUID, areaId: String, coveredFeatureIDs: Set<String>) async throws -> Set<String> {
        coveredFeatureIDs
    }
    func fetchMapFeatures(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        coveredFeatureIDs: Set<String>,
        activeFeatureIDs: Set<String>
    ) async throws -> String {
        #"{"type":"FeatureCollection","features":[]}"#
    }
    func fetchMapCoverageCandidates(points: [TrackPoint]) async throws -> Set<String> { [] }
}
