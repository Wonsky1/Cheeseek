import Combine
import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var nickname: String = ""
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    private let profileService: ProfileServing

    init(profileService: ProfileServing) {
        self.profileService = profileService
        loadProfile()
    }

    func loadProfile() {
        do {
            profile = try profileService.currentProfile()
            if let profile {
                nickname = profile.nickname
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveNickname() async {
        guard !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            profile = try await profileService.relinkOrCreateProfile(nickname: nickname)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
