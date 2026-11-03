import SwiftUI
import ThisJellyFixCore

/// Perfil y Ajustes — the user's personal space in ThisFrame.
///
/// The account card at the top is interactive: tapping it opens
/// `ProfileSettingsView` where the avatar, name, favorites, lists and
/// watched activity can be managed. App-wide settings live in `SettingsView`,
/// reachable from ProfileSettingsView — there is no standalone gear icon on
/// this screen or on the home action pill.
struct ProfileView: View {
    let userName: String
    let onLogout: () -> Void
    var serverURL: URL? = nil
    var token: String? = nil
    var userId: String? = nil

    @State private var showingProfileSettings = false

    /// Jellyfin user avatar (`/Users/{id}/Images/Primary`), tagged with the
    /// session token. Nil when any session piece is missing.
    private var avatarURL: URL? {
        guard let serverURL, let userId, let token, !token.isEmpty else { return nil }
        return serverURL
            .appendingPathComponent("Users/\(userId)/Images/Primary")
            .appending(queryItems: [URLQueryItem(name: "api_key", value: token)])
    }

    private var serverLabel: String {
        guard let serverURL else { return "Jellyfin" }
        return serverURL.host ?? serverURL.absoluteString
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Interactive account card — taps open ProfileSettingsView.
                    Button {
                        showingProfileSettings = true
                    } label: {
                        accountCard
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    logoutButton

                    aboutFooter
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(MareaTheme.Colors.background)
            .navigationTitle("Perfil y Ajustes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // No toolbar gear: settings are reached from ProfileSettingsView.
            .sheet(isPresented: $showingProfileSettings) {
                ProfileSettingsView(
                    userName: userName,
                    serverURL: serverURL,
                    token: token,
                    userId: userId
                )
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MareaTheme.Colors.accent.opacity(0.2))
                    .frame(width: 80, height: 80)
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Image(systemName: "person.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(MareaTheme.Colors.accent)
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(userName)
                    .font(.title2.bold())
                    .lineLimit(1)
                Text("Usuario Jellyfin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(serverLabel, systemImage: "server.rack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5)
        )
    }

    // MARK: - Logout & footer

    private var logoutButton: some View {
        Button {
            onLogout()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Cerrar sesión")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.red)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return version.map { "ThisFrame \($0)" } ?? "ThisFrame"
    }

    private var aboutFooter: some View {
        HStack(spacing: 8) {
            Image("IconoInicio")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(appVersion)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Cliente nativo de Jellyfin")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }
}
