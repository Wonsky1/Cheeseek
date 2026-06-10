import Combine
import Foundation

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published private(set) var sessions: [WalkSession] = []

    private let walkSessionStore: WalkSessionStoring
    private let profileService: ProfileServing

    init(walkSessionStore: WalkSessionStoring, profileService: ProfileServing) {
        self.walkSessionStore = walkSessionStore
        self.profileService = profileService
    }

    func refresh() async {
        do {
            guard let profile = try profileService.currentProfile() else {
                sessions = []
                return
            }
            sessions = try await walkSessionStore.loadSessions()
                .filter { $0.userId == profile.id.uuidString }
                .sorted(by: { $0.startedAt > $1.startedAt })
        } catch {
            sessions = []
        }
    }
}
