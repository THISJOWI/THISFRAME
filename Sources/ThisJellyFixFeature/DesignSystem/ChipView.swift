import SwiftUI

/// Translucent category/metadata pill (Netflix-style chips).
struct ChipView: View {
    let title: String
    var isSelected: Bool = false

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, MareaTheme.Spacing.md)
            .padding(.vertical, MareaTheme.Spacing.xs + 2)
            .background(
                Capsule()
                    .fill(isSelected ? MareaTheme.Colors.accent : MareaTheme.Colors.glass)
            )
            .foregroundStyle(isSelected ? Color.black : Color.primary)
    }
}

#Preview {
    HStack {
        ChipView(title: "Series")
        ChipView(title: "Películas", isSelected: true)
    }
    .padding()
    .background(MareaTheme.Colors.background)
}
