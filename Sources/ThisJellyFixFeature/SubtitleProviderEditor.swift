#if os(iOS) || os(macOS)
import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Inline form to add or edit one subtitle provider.
///
/// The API key is written to the Keychain (never to the preferences file)
/// and is never logged. The form refuses to save a provider that could not
/// work — a missing key is reported instead of silently doing nothing.
struct SubtitleProviderEditor: View {
    let providerID: SubtitleProviderID
    /// True when the provider is not in the store yet.
    let isNew: Bool
    var onSaved: () -> Void = {}
    var onCancel: () -> Void = {}

    @State private var apiKey = ""
    @State private var showKey = false
    @State private var language = ""
    @State private var isEnabled = true
    @State private var errorMessage: String?
    @State private var testing = false
    @State private var testOK: Bool?
    @State private var testMessage: String?

    private let store = SubtitleProviderStore()

    private var descriptor: SubtitleProviderDescriptor? {
        SubtitleProviderCatalog.descriptor(for: providerID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(descriptor?.displayName ?? providerID.rawValue)
                .font(.subheadline.weight(.medium))

            if let summary = descriptor?.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if descriptor?.requiresAPIKey == true {
                apiKeyField
            }

            if descriptor?.isClientSide == true {
                languageField
            }

            Toggle("Usar este proveedor en las búsquedas", isOn: $isEnabled)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Guardar") { save() }
                    .buttonStyle(.bordered)
                    .tint(MareaTheme.Colors.accent)

                Button("Cancelar", action: onCancel)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - Fields

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if showKey {
                    TextField("API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }

            if let url = descriptor?.apiKeyURL {
                Link("Consigue una API key gratis", destination: url)
                    .font(.caption2)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await testConnection() }
                } label: {
                    if testing {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Probar conexión")
                    }
                }
                .buttonStyle(.bordered)
                .tint(MareaTheme.Colors.accent)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testing)

                if let testOK {
                    Label(
                        testOK ? "Conectado" : "Fallo de conexión",
                        systemImage: testOK ? "checkmark.circle" : "xmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(testOK ? .green : .red)
                }
            }

            if let testMessage {
                Text(testMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var languageField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Idioma preferido")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Idioma", selection: $language) {
                Text("Seguir la preferencia de la app").tag("")
                ForEach(LanguagePreferences.pickerCodes, id: \.self) { code in
                    Text(label(for: code)).tag(code)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func label(for code: String) -> String {
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
        if code == LanguagePreferences.systemDefault {
            return "\(name) (sistema)"
        }
        return name
    }

    // MARK: - Actions

    private func load() {
        let key = store.apiKey(for: providerID) ?? ""
        apiKey = key
        showKey = false
        if let config = store.config(for: providerID) {
            isEnabled = config.isEnabled
            language = config.language ?? ""
        } else {
            isEnabled = true
            language = ""
        }
        errorMessage = nil
        testOK = nil
        testMessage = nil
    }

    private func save() {
        errorMessage = nil
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if descriptor?.requiresAPIKey == true, trimmedKey.isEmpty {
            errorMessage = SubtitleProviderError.missingAPIKey.localizedDescription
            return
        }
        if !trimmedKey.isEmpty, trimmedKey.contains(where: { $0.isWhitespace }) {
            errorMessage = SubtitleProviderError.invalidAPIKey.localizedDescription
            return
        }

        do {
            if !trimmedKey.isEmpty || descriptor?.requiresAPIKey == true {
                try store.setAPIKey(trimmedKey, for: providerID)
            }
            let languageCode = language.isEmpty ? nil : language
            if isNew {
                _ = try store.add(providerID, language: languageCode)
            } else if var config = store.config(for: providerID) {
                config.isEnabled = isEnabled
                config.language = languageCode
                try store.update(config)
            } else {
                // The provider was removed while the form was open.
                _ = try store.add(providerID, language: languageCode)
            }
            onSaved()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Real check: one search against the provider with the key that was
    /// typed. The provider's own answer decides, not a guess.
    private func testConnection() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            testOK = false
            testMessage = SubtitleProviderError.missingAPIKey.localizedDescription
            return
        }
        testing = true
        testOK = nil
        testMessage = nil
        defer { testing = false }
        do {
            let count = try await OpenSubtitlesClient(apiKey: key).testConnection()
            testOK = true
            testMessage = "El proveedor respondió con \(count) subtítulos."
        } catch {
            testOK = false
            testMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
#endif
