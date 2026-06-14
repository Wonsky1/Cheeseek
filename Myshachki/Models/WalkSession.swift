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

    init(dto: WalkSessionResponseDTO) {
        self.init(
            id: dto.id,
            startedAt: dto.startedAt,
            endedAt: dto.endedAt,
            distanceMeters: dto.distanceMeters,
            durationSeconds: dto.durationSeconds,
            points: dto.points.map { TrackPoint(dto: $0) },
            userId: dto.userId.uuidString,
            syncStatus: SyncStatus(rawValue: dto.syncStatus) ?? .synced
        )
    }
}
