import SwiftUI

/// Overlay badge anchored to the bottom-left of a media card.
struct BadgeView: View {
    let badge: CardBadge

    var body: some View {
        switch badge {
        case .newEpisodeToday:
            flag(text: "Nuevo hoy", background: MareaTheme.Colors.accent, foreground: .black)
        case .newSeason:
            flag(text: "Nueva temporada", background: MareaTheme.Colors.badgeRed, foreground: .white)
        case .recentlyAdded:
            flag(text: "Recién añadido", background: MareaTheme.Colors.badgeNeutral, foreground: .white)
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

    private func flag(text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(foreground)
            .padding(.horizontal, MareaTheme.Spacing.sm)
            .padding(.vertical, MareaTheme.Spacing.xs)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.small / 2))
    }
}

#Preview {
    VStack(spacing: 12) {
        BadgeView(badge: .newEpisodeToday)
        BadgeView(badge: .newSeason)
        BadgeView(badge: .recentlyAdded)
        BadgeView(badge: .nextEpisode(day: "Domingo"))
    }
    .padding()
    .background(MareaTheme.Colors.background)
}
