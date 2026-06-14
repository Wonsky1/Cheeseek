import ActivityKit
import Foundation

@MainActor
final class WalkLiveActivityService {
    private var activity: Activity<WalkLiveActivityAttributes>?

    func start(startedAt: Date, distanceMeters: Double, elapsedSeconds: TimeInterval) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = Activity<WalkLiveActivityAttributes>.activities.first
        guard activity == nil else {
            update(distanceMeters: distanceMeters, elapsedSeconds: elapsedSeconds, isPaused: false)
            return
        }

        let attributes = WalkLiveActivityAttributes(startedAt: startedAt)
        let state = WalkLiveActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            isPaused: false
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    func update(distanceMeters: Double, elapsedSeconds: TimeInterval, isPaused: Bool) {
        if activity == nil {
            activity = Activity<WalkLiveActivityAttributes>.activities.first
        }
        guard let activity else { return }
        let state = WalkLiveActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            isPaused: isPaused
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end(distanceMeters: Double, elapsedSeconds: TimeInterval) {
        if activity == nil {
            activity = Activity<WalkLiveActivityAttributes>.activities.first
        }
        guard let activity else { return }
        self.activity = nil
        let state = WalkLiveActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            isPaused: false
        )
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
        }
    }
}
