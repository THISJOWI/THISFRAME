import SwiftUI
import ThisJellyFixCore

/// App settings (P8): everything that lived mixed into the profile hub now
/// has its own gear destination. ProfileView keeps identity + favorites +
/// logout; this view owns behavior preferences. Reached from the home action
/// pill and from the profile toolbar.
struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SkipSettingsSection()
                LanguageSettingsSection()
                #if os(iOS) || os(macOS)
                IntegrationsSection()
                #endif
                DiagnosticsSection()
            }
            .padding(.vertical, 16)
        }
        .background(MareaTheme.Colors.background)
        .navigationTitle("Ajustes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Diagnostics

private struct DiagnosticsSection: View {
    private var logURL: URL? {
        let path = TJFLogExport.filePath
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnóstico")
                .font(.headline)

            if let logURL {
                #if !os(tvOS)
                // ShareLink is unavailable on tvOS — the export row is hidden there.
                ShareLink(item: logURL) {
                    Label("Compartir registro de reproducción", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                #endif
                Text("Últimos eventos de reproducción y PiP, sin contraseñas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("El registro aún no existe: reproduce algo primero.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}

// MARK: - Skip Settings

private struct SkipSettingsSection: View {
    // @AppStorage inside @Observable-adjacent views: plain @State-free view,
    // so no @ObservationIgnored needed here.
    @AppStorage(SkipSettings.Key.autoSkip) private var autoSkip = true
    @AppStorage(SkipSettings.Key.intro) private var introEnabled = true
    @AppStorage(SkipSettings.Key.recap) private var recapEnabled = true
    @AppStorage(SkipSettings.Key.credits) private var creditsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Salto automático")
                .font(.headline)

            Toggle(isOn: $autoSkip) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-saltar segmentos")
                    Text("Salta solo tras 5 s dentro de un segmento")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle("Introducción", isOn: $introEnabled)
            Toggle("Resumen", isOn: $recapEnabled)
            Toggle("Ending", isOn: $creditsEnabled)
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}

// MARK: - Language Settings

private struct LanguageSettingsSection: View {
    @AppStorage(LanguagePreferences.Key.audio) private var preferredAudio: String?
    @AppStorage(LanguagePreferences.Key.subtitles) private var preferredSubtitles: String?

    /// None = no preference (player untouched).
    private static let noPreference = ""

    /// Common picker choices + the system language as suggested default.
    private var options: [String] {
        var codes = ["es", "en", "ja", "pt", "fr", "de", "it"]
        if let system = LanguagePreferences.systemDefault, !codes.contains(system) {
            codes.insert(system, at: 0)
        }
        return codes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Idioma")
                .font(.headline)

            Picker("Audio preferido", selection: $preferredAudio) {
                Text("Sin preferencia").tag(String?.some(LanguagePreferences.noPreference))
                ForEach(options, id: \.self) { code in
                    Text(label(for: code)).tag(String?.some(code))
                }
            }

            Divider()

            Picker("Subtítulos preferidos", selection: $preferredSubtitles) {
                Text("Sin preferencia").tag(String?.some(LanguagePreferences.noPreference))
                ForEach(options, id: \.self) { code in
                    Text(label(for: code)).tag(String?.some(code))
                }
            }

            Text("Al abrir un vídeo se elige tu idioma si está disponible. Si cambias dentro del reproductor, se respeta hasta el siguiente.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
        .onAppear {
            // Preselect system language on first run (only if never set).
            if preferredAudio == nil, let system = LanguagePreferences.systemDefault {
                preferredAudio = system
            }
            if preferredSubtitles == nil, let system = LanguagePreferences.systemDefault {
                preferredSubtitles = system
            }
        }
    }

    private func label(for code: String) -> String {
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
        if code == LanguagePreferences.systemDefault {
            return "\(name) (sistema)"
        }
        return name
    }
}
