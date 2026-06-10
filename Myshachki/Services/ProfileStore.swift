import Foundation

protocol ProfileStoring {
    func loadProfile() throws -> UserProfile?
    func saveProfile(_ profile: UserProfile) throws
    func loadDeviceID() throws -> UUID
}

final class ProfileStore: ProfileStoring {
    private let defaults: UserDefaults
    private let profileKey = "myshachki.profile"
    private let deviceIDKey = "myshachki.deviceID"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadProfile() throws -> UserProfile? {
        guard let data = defaults.data(forKey: profileKey) else { return nil }
        return try decoder.decode(UserProfile.self, from: data)
    }

    func saveProfile(_ profile: UserProfile) throws {
        let data = try encoder.encode(profile)
        defaults.set(data, forKey: profileKey)
    }

    func loadDeviceID() throws -> UUID {
        if let string = defaults.string(forKey: deviceIDKey), let uuid = UUID(uuidString: string) {
            return uuid
        }
        let deviceID = UUID()
        defaults.set(deviceID.uuidString, forKey: deviceIDKey)
        return deviceID
    }
}

final class InMemoryProfileStore: ProfileStoring {
    private var storedProfile: UserProfile?
    private let deviceID: UUID

    init(profile: UserProfile? = nil, deviceID: UUID = UUID()) {
        self.storedProfile = profile
        self.deviceID = deviceID
    }

    func loadProfile() throws -> UserProfile? { storedProfile }
    func saveProfile(_ profile: UserProfile) throws { storedProfile = profile }
    func loadDeviceID() throws -> UUID { deviceID }
}
