import Foundation

struct ProfileCreateRequest: Codable {
    let nickname: String
    let deviceId: UUID
}

struct ProfileResponseDTO: Codable {
    let id: UUID
    let nickname: String
    let deviceId: UUID
    let createdAt: Date?
    let updatedAt: Date?
}

struct WalkSessionCreateRequest: Codable {
    let id: UUID
    let userId: UUID
    let startedAt: Date
    let endedAt: Date?
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let syncStatus: String
}

struct TrackPointDTO: Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double
    let timestamp: Date
}

struct TrackPointsUploadRequest: Codable {
    let userId: UUID
    let points: [TrackPointDTO]
}

struct TrackPointsUploadResponse: Codable {
    let saved: Int
    let skippedDuplicates: Int?
}

struct WalkSessionResponseDTO: Codable {
    let id: UUID
    let userId: UUID
    let startedAt: Date
    let endedAt: Date?
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let syncStatus: String
    let points: [TrackPointDTO]
}

struct CoordinateDTO: Codable {
    let latitude: Double
    let longitude: Double
}

struct RouteResponseDTO: Codable {
    let id: UUID
    let userId: UUID
    let title: String
    let coordinates: [CoordinateDTO]
}

struct CoverageUpsertRequestDTO: Codable {
    let userId: UUID
    let areaId: String
    let coveredFeatureIds: [String]
}

struct CoverageResponseDTO: Codable {
    let userId: UUID
    let areaId: String
    let coveredFeatureIds: [String]
    let updatedAt: Date?
}

struct MapCoverageCandidatesRequestDTO: Codable {
    let points: [TrackPointDTO]
}

struct MapCoverageCandidatesResponseDTO: Codable {
    let areaId: String
    let coveredFeatureIds: [String]
}
