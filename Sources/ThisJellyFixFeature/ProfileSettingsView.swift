import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Detailed profile configuration: avatar, name, favorites, lists, watched.
///
/// Reached by tapping the account card on ProfileView. Also hosts the
/// "Ajustes de la app" row that opens `SettingsView`.
struct ProfileSettingsView: View {
    let userName: String
    var serverURL: URL? = nil
    var token: String? = nil
    var userId: String? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var profile: JellyfinUserProfile?
    @State private var displayName: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingEditName = false
    @State private var showingSettings = false

    private let userClient: any JellyfinUserProviding

    private var avatarURL: URL? {
        guard let serverURL, let userId, let token, !token.isEmpty else { return nil }
        return serverURL
            .appendingPathComponent("Users/\(userId)/Images/Primary")
            .appending(queryItems: [URLQueryItem(name: "api_key", value: token)])
    }

    init(
        userName: String,
        serverURL: URL? = nil,
        token: String? = nil,
        userId: String? = nil,
        userClient: any JellyfinUserProviding = JellyfinUserClient()
    ) {
        self.userName = userName
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        self.userClient = userClient
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        ProgressView("Cargando perfil…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                    } else if let errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                            Button("Reintentar") { Task { await loadProfile() } }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else {
                        profileHeader

                        preferencesGroup

                        if let serverURL, let token, let userId {
                            listsSection(serverURL: serverURL, token: token, userId: userId)
                        }

                        settingsRow(
                            icon: "gearshape",
                            title: "Ajustes de la app",
                            subtitle: "Apariencia, reproducción, audio y subtítulos, privacidad"
                        ) {
                            SettingsSectionScreen(title: "Ajustes de la app") {
                                SettingsView()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(MareaTheme.Colors.background)
            .navigationTitle("Configuración del perfil")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .task { await loadProfile() }
            .refreshable { await loadProfile() }
            .sheet(isPresented: $showingEditName) {
                EditProfileNameView(
                    currentName: displayName,
                    userId: userId ?? "",
                    serverURL: serverURL ?? URL(string: "http://localhost")!,
                    token: token ?? "",
                    onSaved: { newName in
                        displayName = newName
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(MareaTheme.Colors.accent.opacity(0.2))
                        .frame(width: 88, height: 88)
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(MareaTheme.Colors.accent)
                        }
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())

                    changePhotoButton
                        .offset(x: 28, y: 28)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName.isEmpty ? (profile?.name ?? userName) : displayName)
                        .font(.title2.bold())
                        .lineLimit(1)

                    if let profile, profile.isAdministrator {
                        Label("Administrador", systemImage: "shield.fill")
                            .font(.caption2)
                            .foregroundStyle(MareaTheme.Colors.accentText)
                    }

                    if let lastLogin = profile?.lastLoginDate {
                        Label("Última sesión: \(lastLogin)", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    showingEditName = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Editar nombre")
            }

            Divider()
        }
    }

    @ViewBuilder
    private var changePhotoButton: some View {
        Button {
            // Photo picker integration would go here (PHPickerViewController).
            // Requires UIKit bridging — not yet wired.
        } label: {
            Image(systemName: "camera")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(MareaTheme.Colors.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cambiar foto de perfil")
    }

    @ViewBuilder
    private var preferencesGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preferencias")
                .font(.title3.bold())
                .padding(.horizontal, 4)

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
            }
            .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func listsSection(
        serverURL: URL,
        token: String,
        userId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tus listas")
                .font(.title3.bold())
                .padding(.horizontal, 4)

            NavigationLink {
                ListsView(
                    serverURL: serverURL,
                    token: token,
                    userId: userId
                )
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MareaTheme.Colors.accentText)
                        .frame(width: 36, height: 36)
                        .background(
                            MareaTheme.Colors.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listas personales")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Crea y organiza tus propias listas de contenido")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
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

    // MARK: - Actions

    private func loadProfile() async {
        guard let serverURL, let userId, let token else {
            isLoading = false
            displayName = userName
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            profile = try await userClient.fetchProfile(
                userId: userId,
                serverURL: serverURL,
                token: token
            )
            displayName = profile?.name ?? userName
            errorMessage = nil
        } catch {
            displayName = userName
            errorMessage = error.localizedDescription
        }
    }
}

/// Reusable destination shell for settings sections.
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

/// Edit the user's display name via `POST /Users/{id}`.
private struct EditProfileNameView: View {
    let currentName: String
    let userId: String
    let serverURL: URL
    let token: String
    var onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client: any JellyfinUserProviding

    init(
        currentName: String,
        userId: String,
        serverURL: URL,
        token: String,
        client: any JellyfinUserProviding = JellyfinUserClient(),
        onSaved: @escaping (String) -> Void
    ) {
        self.currentName = currentName
        self.userId = userId
        self.serverURL = serverURL
        self.token = token
        self.client = client
        self.onSaved = onSaved
        _name = State(initialValue: currentName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Nombre", text: $name)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Editar nombre")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        ProgressView("Guardando…")
                    }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await client.updateName(
                userId: userId,
                name: trimmed,
                serverURL: serverURL,
                token: token
            )
            onSaved(trimmed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
