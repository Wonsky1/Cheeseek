import SwiftUI

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var prominent: Bool = true
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.headline)
                }
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(prominent ? Color.blue : Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(prominent ? 0 : 0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}
