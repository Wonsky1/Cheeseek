import SwiftUI

struct LiveWalkCard: View {
    let elapsedTime: TimeInterval
    let distance: Double
    let gpsStatus: String
    let syncStatus: String
    let isPaused: Bool
    let isFinishing: Bool
    let pauseAction: () -> Void
    let finishAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(isPaused ? "PAUSED" : "LIVE", systemImage: isPaused ? "pause.circle.fill" : "location.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isPaused ? Color.orange : Color.red)
                Spacer()
                Text(syncStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                stat(title: "Time", value: elapsedTime.formattedClock)
                stat(title: "Distance", value: distance.formattedDistance)
                stat(title: "GPS", value: gpsStatus)
            }
            HStack(spacing: 12) {
                PrimaryButton(
                    title: isPaused ? "Resume" : "Pause",
                    icon: isPaused ? "play.fill" : "pause.fill",
                    prominent: false,
                    isDisabled: isFinishing,
                    action: pauseAction
                )
                PrimaryButton(
                    title: isFinishing ? "Finishing..." : "Finish",
                    icon: "flag.checkered",
                    isDisabled: isFinishing,
                    action: finishAction
                )
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
