import Foundation

struct SharedProgress: Codable, Equatable {
    var totalDistanceMeters: Double
    var totalWalks: Int
    var completedRoutesPlaceholder: Int
    var explorationProgressPercentPlaceholder: Double

    static let placeholder = SharedProgress(
        totalDistanceMeters: 0,
        totalWalks: 0,
        completedRoutesPlaceholder: 0,
        explorationProgressPercentPlaceholder: 0
    )
}
