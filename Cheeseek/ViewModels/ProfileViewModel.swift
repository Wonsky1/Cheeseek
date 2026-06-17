import Combine
import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var nickname: String = ""
    @Published var serverBaseURLText: String = ""
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isSaving = false
    @Published private(set) var isSavingServerURL = false
    @Published private(set) var errorMessage: String?

    private let profileService: ProfileServing
    private let serverConfiguration: ServerConfiguration

    init(profileService: ProfileServing, serverConfiguration: ServerConfiguration) {
        self.profileService = profileService
        self.serverConfiguration = serverConfiguration
        self.serverBaseURLText = serverConfiguration.baseURLString
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

    var canSaveServerURL: Bool {
        !isSavingServerURL && normalizedServerURLInput != serverConfiguration.baseURLString
    }

    func saveServerBaseURL() {
        guard canSaveServerURL else { return }
        isSavingServerURL = true
        errorMessage = nil
        defer { isSavingServerURL = false }
        do {
            try serverConfiguration.updateBaseURL(from: serverBaseURLText)
            serverBaseURLText = serverConfiguration.baseURLString
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var normalizedServerURLInput: String {
        serverBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
