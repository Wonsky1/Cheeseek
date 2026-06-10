import SwiftUI

struct MapOverlayLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(color: .yellow, label: "Explored")
            item(color: .purple, label: "Now")
            item(color: .cyan, label: "GPS")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }

    private func item(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}
