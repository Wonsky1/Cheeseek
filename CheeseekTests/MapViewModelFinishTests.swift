import XCTest
@testable import Cheeseek

@MainActor
final class MapViewModelFinishTests: XCTestCase {
    func testFinishWalkShowsSummaryAfterBackendAcceptsWalk() async throws {
        let profile = UserProfile(id: UUID(), nickname: "admin", deviceId: UUID(), createdAt: .now)
        let backendSyncService = RecordingBackendSyncService()
        let viewModel = MapViewModel(
            locationManager: .preview,
            coverageStore: InMemoryCoverageStore(),
            backendSyncService: backendSyncService,
            mockRouteProvider: MockRouteProvider(),
            profileService: PreviewProfileService(profileStore: InMemoryProfileStore(profile: profile)),
            walkLiveActivityService: WalkLiveActivityService()
        )

        viewModel.refreshProfile()
        viewModel.startWalk()
        viewModel.adminStepNorth()

        try await finishWithin(0.5) {
            await viewModel.finishWalk()
        }

        XCTAssertEqual(backendSyncService.syncedSessions.count, 1)
        XCTAssertEqual(viewModel.storedSessions.count, 1)
        XCTAssertEqual(viewModel.summarySession?.id, backendSyncService.syncedSessions.first?.id)
        XCTAssertEqual(viewModel.walkState, .finished(backendSyncService.syncedSessions[0]))
        XCTAssertFalse(viewModel.isFinishingWalk)
        XCTAssertEqual(viewModel.syncStatusText, SyncStatus.synced.label)
    }

    func testActivityRefreshShowsBackendWalksOnly() async throws {
        let profile = UserProfile(id: UUID(), nickname: "admin", deviceId: UUID(), createdAt: .now)
        let session = finishedSession(userId: profile.id.uuidString)
        let backendSyncService = RecordingBackendSyncService(remoteSessions: [session])
        let viewModel = ActivityViewModel(
            profileService: PreviewProfileService(profileStore: InMemoryProfileStore(profile: profile)),
            backendSyncService: backendSyncService
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.sessions[0].id, session.id)
        XCTAssertNil(viewModel.statusText)
    }

    private func finishWithin(_ seconds: TimeInterval, operation: @escaping () async -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw FinishTimeoutError.timedOut
            }

            try await group.next()
            group.cancelAll()
        }
    }

    private func finishedSession(userId: String) -> WalkSession {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var session = WalkSession.fresh(userId: userId, startedAt: startedAt)
        session.endedAt = startedAt.addingTimeInterval(60)
        session.durationSeconds = 60
        session.distanceMeters = 25
        session.syncStatus = .readyToSync
        session.points = [
            TrackPoint(
                id: UUID(),
                latitude: 52.2297,
                longitude: 21.0122,
                altitude: nil,
                horizontalAccuracy: 5,
                timestamp: startedAt
            ),
            TrackPoint(
                id: UUID(),
                latitude: 52.22982,
                longitude: 21.0122,
                altitude: nil,
                horizontalAccuracy: 5,
                timestamp: startedAt.addingTimeInterval(30)
            )
        ]
        return session
    }
}

private enum FinishTimeoutError: Error {
    case timedOut
}

private final class RecordingBackendSyncService: BackendSyncServing {
    private(set) var syncedSessions: [WalkSession]
    private var remoteSessions: [WalkSession]

    init(remoteSessions: [WalkSession] = []) {
        self.syncedSessions = []
        self.remoteSessions = remoteSessions
    }

    func syncWalkSession(_ session: WalkSession) async throws {
        var syncedSession = session
        syncedSession.syncStatus = .synced
        syncedSessions.append(syncedSession)
        if let index = remoteSessions.firstIndex(where: { $0.id == session.id }) {
            remoteSessions[index] = syncedSession
        } else {
            remoteSessions.append(syncedSession)
        }
    }

    func fetchWalkSessions(userId: UUID) async throws -> [WalkSession] {
        remoteSessions.filter { $0.userId == userId.uuidString }
    }

    func fetchSharedProgress() async throws -> SharedProgress {
        .placeholder
    }

    func uploadTrackPoints(sessionId: UUID, userId: UUID, points: [TrackPoint]) async throws {}

    func fetchCoverage(userId: UUID, areaId: String) async throws -> Set<String> {
        []
    }

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

    func fetchMapCoverageCandidates(points: [TrackPoint]) async throws -> Set<String> {
        []
    }
}
