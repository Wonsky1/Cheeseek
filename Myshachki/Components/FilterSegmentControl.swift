import SwiftUI

struct FilterSegmentControl: View {
    @Binding var selection: MapFilter

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MapFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(selection == filter ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(selection == filter ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
    }
}
