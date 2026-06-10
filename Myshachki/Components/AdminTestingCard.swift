import SwiftUI

struct AdminTestingCard: View {
    let canReset: Bool
    let prepareAction: () -> Void
    let resetAction: () -> Void
    let northAction: () -> Void
    let southAction: () -> Void
    let eastAction: () -> Void
    let westAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            stepButton(systemName: "arrow.up", action: northAction)
            stepButton(systemName: "arrow.left", action: westAction)
            stepButton(systemName: "arrow.right", action: eastAction)
            stepButton(systemName: "arrow.down", action: southAction)

            Button {
                if canReset {
                    resetAction()
                } else {
                    prepareAction()
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.1), radius: 12, y: 6)
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        RepeatingStepButton(systemName: systemName, action: action)
    }
}

private struct RepeatingStepButton: View {
    let systemName: String
    let action: () -> Void

    @State private var holdTimer: Timer?
    @State private var isHolding = false

    var body: some View {
        Image(systemName: systemName)
            .font(.caption.weight(.semibold))
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(isHolding ? 0.72 : 0.9), in: Circle())
            .contentShape(Circle())
            .foregroundStyle(.primary)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        startRepeatingIfNeeded()
                    }
                    .onEnded { _ in
                        stopRepeating()
                    }
            )
            .onDisappear {
                stopRepeating()
            }
    }

    private func startRepeatingIfNeeded() {
        guard !isHolding else { return }
        isHolding = true
        action()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { _ in
            action()
        }
    }

    private func stopRepeating() {
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
    }
}
