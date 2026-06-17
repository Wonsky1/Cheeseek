import Foundation

struct UserProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var nickname: String
    var deviceId: UUID
    var createdAt: Date?
}
