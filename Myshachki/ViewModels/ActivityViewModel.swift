import Combine
import Foundation

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published private(set) var sessions: [WalkSession] = []
    @Published private(set) var statusText: String?

    private let walkSessionStore: WalkSessionStoring
    private let profileService: ProfileServing
    private let backendSyncService: BackendSyncServing

    init(
        walkSessionStore: WalkSessionStoring,
        profileService: ProfileServing,
        backendSyncService: BackendSyncServing
    ) {
        self.walkSessionStore = walkSessionStore
        self.profileService = profileService
        self.backendSyncService = backendSyncService
    }

    func refresh() async {
        do {
            guard let profile = try profileService.currentProfile() else {
                sessions = []
                statusText = "Create or relink your nickname first."
                return
            }
            let allLocalSessions = try await walkSessionStore.loadSessions()
            var localSessions = allLocalSessions
                .filter { $0.userId == profile.id.uuidString }
            localSessions = await syncPendingSessions(localSessions)

            do {
                let remoteSessions = try await backendSyncService.fetchWalkSessions(userId: profile.id)
                let mergedSessions = merged(localSessions: localSessions, remoteSessions: remoteSessions)
                try await replaceSessions(for: profile.id, with: mergedSessions)
                sessions = mergedSessions.sorted(by: { $0.startedAt > $1.startedAt })
                statusText = nil
            } catch {
                sessions = localSessions.sorted(by: { $0.startedAt > $1.startedAt })
                statusText = "Showing local walks. Server sync unavailable."
            }
        } catch {
            sessions = []
            statusText = error.localizedDescription
        }
    }

    private func syncPendingSessions(_ localSessions: [WalkSession]) async -> [WalkSession] {
        var updatedSessions = localSessions
        for index in updatedSessions.indices {
            guard updatedSessions[index].isFinished else { continue }
            guard updatedSessions[index].syncStatus != .synced else { continue }
            guard updatedSessions[index].points.count > 1 else { continue }
            do {
                updatedSessions[index].syncStatus = .syncing
                try await walkSessionStore.saveSession(updatedSessions[index])
                try await backendSyncService.syncWalkSession(updatedSessions[index])
                updatedSessions[index].syncStatus = .synced
                try await walkSessionStore.saveSession(updatedSessions[index])
            } catch {
                updatedSessions[index].syncStatus = .failed
                try? await walkSessionStore.saveSession(updatedSessions[index])
            }
        }
        return updatedSessions
    }

    private func merged(localSessions: [WalkSession], remoteSessions: [WalkSession]) -> [WalkSession] {
        var sessionsByID = Dictionary(uniqueKeysWithValues: localSessions.map { ($0.id, $0) })
        for remoteSession in remoteSessions {
            if let localSession = sessionsByID[remoteSession.id] {
                sessionsByID[remoteSession.id] = preferredSession(local: localSession, remote: remoteSession)
            } else {
                sessionsByID[remoteSession.id] = remoteSession
            }
        }
        return Array(sessionsByID.values)
    }

    private func replaceSessions(for userID: UUID, with userSessions: [WalkSession]) async throws {
        let otherSessions = try await walkSessionStore.loadSessions()
            .filter { $0.userId != userID.uuidString }
        try await walkSessionStore.replaceSessions(otherSessions + userSessions)
    }

    private func preferredSession(local: WalkSession, remote: WalkSession) -> WalkSession {
        var chosen = remote.points.count >= local.points.count ? remote : local
        if local.syncStatus == .synced || remote.syncStatus == .synced {
            chosen.syncStatus = .synced
        }
        return chosen
    }
}
