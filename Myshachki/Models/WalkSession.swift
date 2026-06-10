import Foundation

struct WalkSession: Identifiable, Codable, Equatable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double
    var durationSeconds: TimeInterval
    var points: [TrackPoint]
    var userId: String
    var syncStatus: SyncStatus
}

extension WalkSession {
    var isFinished: Bool {
        endedAt != nil
    }

    static func fresh(userId: String, startedAt: Date = .now) -> WalkSession {
        WalkSession(
            id: UUID(),
            startedAt: startedAt,
            endedAt: nil,
            distanceMeters: 0,
            durationSeconds: 0,
            points: [],
            userId: userId,
            syncStatus: .localOnly
        )
    }
}
