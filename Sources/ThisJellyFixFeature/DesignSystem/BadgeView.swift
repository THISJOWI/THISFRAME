import SwiftUI

/// Overlay badge anchored to the bottom-left of a media card.
struct BadgeView: View {
    let badge: CardBadge

    var body: some View {
        switch badge {
        case .newSeason:
            Text("Nueva temporada")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, MareaTheme.Spacing.sm)
                .padding(.vertical, MareaTheme.Spacing.xs)
                .background(MareaTheme.Colors.badgeRed)
                .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.small / 2))
        case .nextEpisode(let day):
            VStack(spacing: 0) {
                Text("Siguiente episodio")
                    .font(.caption2.bold())
                    .foregroundStyle(MareaTheme.Colors.badgeRed)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, MareaTheme.Spacing.sm)
                    .padding(.vertical, MareaTheme.Spacing.xs)
                    .background(.white)
                if let day {
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, MareaTheme.Spacing.sm)
                        .padding(.vertical, MareaTheme.Spacing.xs)
                        .background(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.small / 2))
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        BadgeView(badge: .newSeason)
        BadgeView(badge: .nextEpisode(day: "Domingo"))
    }
    .padding()
    .background(MareaTheme.Colors.background)
}
