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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar — the user's Jellyfin picture, falling back to
                    // the generic icon when the account has none.
                    ZStack {
                        Circle()
                            .fill(MareaTheme.Colors.accent.opacity(0.2))
                            .frame(width: 100, height: 100)
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: "person.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(MareaTheme.Colors.accent)
                            }
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                    }
                    .padding(.top, 24)

                    VStack(spacing: 4) {
                        Text(userName)
                            .font(.title2.bold())
                        Text("Usuario Jellyfin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Favorites section
                    if let serverURL, let token, let userId {
                        FavoritesView(serverURL: serverURL, token: token, userId: userId)
                            .frame(height: 300)
                    }

                    // Server
                    if let serverURL {
                        Label(serverURL.host ?? serverURL.absoluteString, systemImage: "server.rack")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
