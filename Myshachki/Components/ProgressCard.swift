import SwiftUI

struct ProgressCard: View {
    let progress: SharedProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exploration")
                .font(.headline)
            HStack {
                metric(title: "Buildings", value: "\(progress.completedRoutesPlaceholder)")
                metric(title: "Distance", value: progress.totalDistanceMeters.formattedDistance)
                metric(title: "Walks", value: "\(progress.totalWalks)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 18, y: 8)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
