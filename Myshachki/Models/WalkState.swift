import Foundation

enum WalkState: Equatable {
    case idle
    case recording
    case paused
    case finished(WalkSession)
}
