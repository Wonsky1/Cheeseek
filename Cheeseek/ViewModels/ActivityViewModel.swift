import Combine
import Foundation

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published private(set) var sessions: [WalkSession] = []
    @Published private(set) var statusText: String?

    private let profileService: ProfileServing
    private let backendSyncService: BackendSyncServing

    init(
        profileService: ProfileServing,
        backendSyncService: BackendSyncServing
    ) {
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
            do {
                let remoteSessions = try await backendSyncService.fetchWalkSessions(userId: profile.id)
                sessions = remoteSessions.sorted(by: { $0.startedAt > $1.startedAt })
                statusText = nil
            } catch {
                sessions = []
                statusText = "Server unavailable. Walk history lives on the backend."
            }
        } catch {
            sessions = []
            statusText = error.localizedDescription
        }
    }
}
