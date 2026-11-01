import SwiftUI
import ThisJellyFixCore

struct ProfileView: View {
    let userName: String
    let onLogout: () -> Void
    var serverURL: URL? = nil
    var token: String? = nil
    var userId: String? = nil

    /// Jellyfin user avatar (`/Users/{id}/Images/Primary`), tagged with the
    /// session token. Nil when any session piece is missing.
    private var avatarURL: URL? {
        guard let serverURL, let userId, let token, !token.isEmpty else { return nil }
        return serverURL
            .appendingPathComponent("Users/\(userId)/Images/Primary")
            .appending(queryItems: [URLQueryItem(name: "api_key", value: token)])
    }

    private var accountCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MareaTheme.Colors.accent.opacity(0.2))
                    .frame(width: 74, height: 74)
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Image(systemName: "person.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(MareaTheme.Colors.accent)
                    }
                }
                .frame(width: 74, height: 74)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(userName)
                    .font(.title2.bold())
                Text("Usuario Jellyfin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let serverURL {
                    Label(serverURL.host ?? serverURL.absoluteString, systemImage: "server.rack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(18)
        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: MareaTheme.Radius.card)
                .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    accountCard
                        .padding(.top, 12)

                    NavigationLink(destination: SettingsView()) {
                        HStack(spacing: 14) {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(MareaTheme.Colors.accentText)
                                .frame(width: 38, height: 38)
                                .background(MareaTheme.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ajustes de la app")
                                    .font(.headline)
                                Text("Apariencia, reproducción, audio y conexiones")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: MareaTheme.Radius.card)
                                .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    // Favorites section
                    if let serverURL, let token, let userId {
                        FavoritesView(serverURL: serverURL, token: token, userId: userId)
                            .frame(height: 300)
                    }

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            onLogout()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Cerrar sesión")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 32)
                }
            }
            .background(MareaTheme.Colors.background)
            .navigationTitle("Perfil")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Behavior preferences live in their own destination (P8).
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ajustes")
                }
            }
        }
    }
}
