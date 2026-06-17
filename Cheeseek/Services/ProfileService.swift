import Foundation

protocol ProfileServing {
    func currentProfile() throws -> UserProfile?
    func relinkOrCreateProfile(nickname: String) async throws -> UserProfile
    func deviceID() throws -> UUID
}

struct EmptyResponse: Decodable {}

@MainActor
final class ProfileService: ProfileServing {
    private let apiClient: APIClient
    private let profileStore: ProfileStoring

    init(apiClient: APIClient, profileStore: ProfileStoring) {
        self.apiClient = apiClient
        self.profileStore = profileStore
    }

    func currentProfile() throws -> UserProfile? {
        try profileStore.loadProfile()
    }

    func relinkOrCreateProfile(nickname: String) async throws -> UserProfile {
        let request = ProfileCreateRequest(
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceId: try profileStore.loadDeviceID()
        )
        let response: ProfileResponseDTO = try await apiClient.post("/profiles", body: request)
        let profile = UserProfile(
            id: response.id,
            nickname: response.nickname,
            deviceId: response.deviceId,
            createdAt: response.createdAt
        )
        try profileStore.saveProfile(profile)
        return profile
    }

    func deviceID() throws -> UUID {
        try profileStore.loadDeviceID()
    }
}

@MainActor
final class PreviewProfileService: ProfileServing {
    private let profileStore: ProfileStoring

    init(profileStore: ProfileStoring) {
        self.profileStore = profileStore
    }

    func currentProfile() throws -> UserProfile? {
        try profileStore.loadProfile()
    }

    func relinkOrCreateProfile(nickname: String) async throws -> UserProfile {
        let profile = UserProfile(id: UUID(), nickname: nickname, deviceId: try profileStore.loadDeviceID(), createdAt: .now)
        try profileStore.saveProfile(profile)
        return profile
    }

    func deviceID() throws -> UUID {
        try profileStore.loadDeviceID()
    }
}
