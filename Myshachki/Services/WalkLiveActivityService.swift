import ActivityKit
import Foundation

@MainActor
final class WalkLiveActivityService {
    private var activity: Activity<WalkLiveActivityAttributes>?
    private var startTask: Task<Void, Never>?

    func start(startedAt: Date, distanceMeters: Double, elapsedSeconds: TimeInterval) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        startTask?.cancel()
        activity = nil
        let attributes = WalkLiveActivityAttributes(startedAt: startedAt)
        let state = WalkLiveActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            isPaused: false
        )

        startTask = Task { @MainActor [weak self] in
            for existingActivity in Activity<WalkLiveActivityAttributes>.activities {
                await existingActivity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
            guard !Task.isCancelled else { return }
            do {
                self?.activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil)
                )
            } catch {
                self?.activity = nil
            }
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
        startTask?.cancel()
        startTask = nil
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
