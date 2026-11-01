import SwiftUI
import ThisJellyFixCore
#if os(iOS)
import ThisJellyFixCast
#endif

/// Profile and settings in one destination.
///
/// The account identity stays at the top, then every preference is grouped
/// into native rows. Each row pushes the existing settings section, so no
/// option is duplicated or lost: the full SettingsView is still reachable
/// from the toolbar gear.
struct ProfileView: View {
    let userName: String
    let onLogout: () -> Void
    var serverURL: URL? = nil
    var token: String? = nil
    var userId: String? = nil

    @State private var showsFullSettings = false

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
                    accountCard
                        .padding(.top, 8)

                    preferencesGroup

                    if let serverURL, let token, let userId {
                        favoritesSection(serverURL: serverURL, token: token, userId: userId)
                    }

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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Todos los ajustes")
                }
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MareaTheme.Colors.accent.opacity(0.2))
                    .frame(width: 76, height: 76)
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
                .frame(width: 76, height: 76)
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
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5)
        )
    }

    // MARK: - Preferences

    private var preferencesGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupHeader("Preferencias")

            VStack(spacing: 0) {
                settingsRow(
                    icon: "circle.lefthalf.filled",
                    title: "Apariencia",
                    subtitle: "Claro, oscuro o según el sistema"
                ) {
                    SettingsSectionScreen(title: "Apariencia") {
                        AppearanceSettingsSection()
                    }
                }

                rowDivider

                settingsRow(
                    icon: "play.circle",
                    title: "Reproducción",
                    subtitle: "Salto automático de introducción, resumen y ending"
                ) {
                    SettingsSectionScreen(title: "Reproducción") {
                        SkipSettingsSection()
                    }
                }

                rowDivider

                settingsRow(
                    icon: "captions.bubble",
                    title: "Audio y subtítulos",
                    subtitle: "Tamaño, idioma preferido y proveedores"
                ) {
                    SettingsSectionScreen(title: "Audio y subtítulos") {
                        VStack(spacing: 16) {
                            SubtitleSizeSettingsSection()
                            LanguageSettingsSection()
                            #if os(iOS) || os(macOS)
                            SubtitleProvidersSection()
                            #endif
                        }
                    }
                }

                rowDivider

                settingsRow(
                    icon: "server.rack",
                    title: "Conexión con Jellyfin",
                    subtitle: serverLabel
                ) {
                    SettingsSectionScreen(title: "Conexión con Jellyfin") {
                        JellyfinConnectionSection(
                            userName: userName,
                            serverURL: serverURL
                        )
                    }
                }

                rowDivider

                settingsRow(
                    icon: "airplayvideo",
                    title: "Dispositivos y transmisión",
                    subtitle: "AirPlay y dispositivos disponibles"
                ) {
                    SettingsSectionScreen(title: "Dispositivos y transmisión") {
                        TransmissionSection()
                    }
                }

                #if os(iOS) || os(macOS)
                rowDivider

                settingsRow(
                    icon: "puzzlepiece.extension",
                    title: "Integraciones",
                    subtitle: "TMDB, Radarr y Sonarr"
                ) {
                    SettingsSectionScreen(title: "Integraciones") {
                        IntegrationsSection()
                    }
                }
                #endif

                rowDivider

                settingsRow(
                    icon: "hand.raised",
                    title: "Privacidad y diagnóstico",
                    subtitle: "Datos locales y registro de reproducción"
                ) {
                    SettingsSectionScreen(title: "Privacidad") {
                        VStack(spacing: 16) {
                            PrivacySection()
                            DiagnosticsSection()
                        }
                    }
                }

                rowDivider

                settingsRow(
                    icon: "info.circle",
                    title: "Acerca de ThisFrame",
                    subtitle: appVersion
                ) {
                    SettingsSectionScreen(title: "Acerca de ThisFrame") {
                        AboutThisFrameSection()
                    }
                }
            }
            .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5)
            )
        }
    }

    private func settingsRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MareaTheme.Colors.accentText)
                    .frame(width: 36, height: 36)
                    .background(
                        MareaTheme.Colors.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 64)
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    // MARK: - Favorites

    private func favoritesSection(
        serverURL: URL,
        token: String,
        userId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            groupHeader("Favoritos")
            FavoritesView(
                serverURL: serverURL,
                token: token,
                userId: userId,
                embedded: true
            )
        }
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

// MARK: - Reusable destination shell

private struct SettingsSectionScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(.vertical, 16)
        }
        .background(MareaTheme.Colors.background)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Jellyfin connection

private struct JellyfinConnectionSection: View {
    let userName: String
    let serverURL: URL?

    private var serverLabel: String {
        guard let serverURL else { return "Sin servidor" }
        return serverURL.host ?? serverURL.absoluteString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sesión")
                .font(.headline)

            infoRow(icon: "person.crop.circle", title: "Usuario", value: userName)
            Divider()
            infoRow(icon: "server.rack", title: "Servidor", value: serverLabel)
            Divider()
            infoRow(icon: "lock.shield", title: "Credenciales", value: "Guardadas en el Llavero")

            Text("La sesión se mantiene en este dispositivo y se renueva contra tu servidor Jellyfin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(MareaTheme.Colors.accentText)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Devices & transmission

private struct TransmissionSection: View {
    #if os(iOS)
    @ObservedObject private var cast = CastController.shared
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transmisión")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: "airplayvideo")
                    .font(.title3)
                    .foregroundStyle(MareaTheme.Colors.accentText)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AirPlay")
                        .font(.subheadline.weight(.medium))
                    Text("Elige el dispositivo desde el reproductor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            #if os(iOS)
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(MareaTheme.Colors.accentText)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Cast")
                        .font(.subheadline.weight(.medium))
                    Text(cast.manager.state.isConnected ? "Conectado" : "Sin dispositivo conectado")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            #endif
        }
        .padding(16)
        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}

// MARK: - Privacy

private struct PrivacySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacidad")
                .font(.headline)
            Text("ThisFrame se conecta únicamente a tu servidor Jellyfin y a los servicios que configures. Las credenciales viven en el Llavero del dispositivo y los registros de reproducción no incluyen contraseñas.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}

// MARK: - About

private struct AboutThisFrameSection: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image("IconoInicio")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ThisFrame")
                        .font(.headline)
                    Text("Tu experiencia de streaming, renovada.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Text("Versión")
                Spacer()
                Text("\(version) (\(build))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            HStack {
                Text("Plataforma")
                Spacer()
                Text(platformName)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Text("Cliente nativo de Jellyfin construido con SwiftUI. Sin webviews.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private var platformName: String {
        #if os(iOS)
        "iPhone / iPad"
        #elseif os(macOS)
        "macOS"
        #elseif os(tvOS)
        "Apple TV"
        #elseif os(visionOS)
        "visionOS"
        #else
        "Apple"
        #endif
    }
}
