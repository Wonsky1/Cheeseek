import ActivityKit
import SwiftUI
import WidgetKit

struct WalkLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkLiveActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.walk")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.yellow)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.state.isPaused ? "Paused" : "Walking")
                        .font(.headline)
                    HStack(spacing: 12) {
                        Label(formatDistance(context.state.distanceMeters), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        Label {
                            liveElapsedText(context)
                        } icon: {
                            Image(systemName: "timer")
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.88))
            .activitySystemActionForegroundColor(.yellow)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.isPaused ? "pause.fill" : "figure.walk")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.yellow)
                            .frame(width: 28, height: 28)
                            .background(Color.yellow.opacity(0.16), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.isPaused ? "Paused" : "Walking")
                                .font(.caption.weight(.semibold))
                            Text(context.state.isPaused ? "Ready to resume" : "Live walk")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        liveElapsedText(context)
                            .font(.headline.monospacedDigit().weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        dynamicIslandMetric(
                            title: "Distance",
                            value: formatDistance(context.state.distanceMeters),
                            icon: "point.topleft.down.curvedto.point.bottomright.up"
                        )
                        dynamicIslandMetric(
                            title: "Status",
                            value: context.state.isPaused ? "Paused" : "In progress",
                            icon: context.state.isPaused ? "pause.fill" : "location.fill"
                        )
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.walk")
                    .foregroundStyle(.yellow)
            } compactTrailing: {
                Text(formatCompactDistance(context.state.distanceMeters))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.yellow)
            }
        }
    }

    private func dynamicIslandMetric(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.yellow)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private func formatCompactDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fk", meters / 1000)
        }
        return "\(Int(meters.rounded()))m"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @ViewBuilder
    private func liveElapsedText(_ context: ActivityViewContext<WalkLiveActivityAttributes>) -> some View {
        if context.state.isPaused {
            Text(formatTime(context.state.elapsedSeconds))
        } else {
            Text(context.attributes.startedAt, style: .timer)
        }
    }
}
