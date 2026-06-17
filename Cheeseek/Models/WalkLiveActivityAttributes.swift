import ActivityKit
import Foundation

struct WalkLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var elapsedSeconds: TimeInterval
        var isPaused: Bool
    }

    var startedAt: Date
}
