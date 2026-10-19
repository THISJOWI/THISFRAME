#if os(iOS) || os(macOS)
import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Settings section for the subtitle providers.
///
/// Two kinds of provider share one list:
/// - the **server's own** providers (the OpenSubtitles plugin and friends).
///   They need no credentials and are always listed.
/// - the providers the **app** queries itself (OpenSubtitles.com). The user
///   adds them and their API key lives in the Keychain, never in the
///   preferences file.
struct SubtitleProvidersSection: View {
    /// What the section is showing right now.
    private enum Mode: Equatable {
        case list
        case picking
        case editing(SubtitleProviderID, isNew: Bool)
    }

    @State private var mode: Mode = .list
    @State private var configs: [SubtitleProviderConfig] = []

    private let store = SubtitleProviderStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proveedores de subtítulos")
                .font(.headline)

            switch mode {
            case .list:
                listContent
            case .picking:
                pickerContent
            case .editing(let id, let isNew):
                SubtitleProviderEditor(
                    providerID: id,
                    isNew: isNew,
                    onSaved: {
                        reload()
                        mode = .list
                    },
                    onCancel: {
                        mode = .list
                    }
                )
                // A fresh form per provider: the state (the key, the
                // language) must never leak from one provider to the next.
                .id(id)
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
        .onAppear(perform: reload)
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        ForEach(configs) { config in
            providerRow(config)
            if config.id != configs.last?.id {
                Divider()
            }
        }

        Button {
            mode = .picking
        } label: {
            Label("Añadir proveedor", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(MareaTheme.Colors.accent)
        .disabled(configs.count >= SubtitleProviderCatalog.all.count)

        Text("Los proveedores del servidor se configuran en el panel web de Jellyfin. Los que añade la app se consultan directamente con tu API key, que se guarda en el Keychain del dispositivo.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func providerRow(_ config: SubtitleProviderConfig) -> some View {
        let descriptor = SubtitleProviderCatalog.descriptor(for: config.id)
        let configured = store.isConfigured(config.id)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor?.displayName ?? config.id.rawValue)
                        .font(.subheadline.weight(.medium))
                    Text(statusText(config: config, configured: configured))
                        .font(.caption)
                        .foregroundStyle(configured ? Color.secondary : Color.orange)
                }
                Spacer()
                Toggle("Usar en las búsquedas", isOn: Binding(
                    get: { config.isEnabled },
                    set: { newValue in
                        try? store.setEnabled(newValue, for: config.id)
                        reload()
                    }
                ))
                .labelsHidden()
            }

            HStack(spacing: 12) {
                Button("Editar") {
                    mode = .editing(config.id, isNew: false)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(MareaTheme.Colors.accent)

                if descriptor?.isRemovable == true {
                    Button("Eliminar", role: .destructive) {
                        try? store.remove(config.id)
                        reload()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func statusText(config: SubtitleProviderConfig, configured: Bool) -> String {
        guard configured else {
            return SubtitleProviderCatalog.descriptor(for: config.id)?.requiresAPIKey == true
                ? "Falta la API key — el proveedor no se usará en las búsquedas."
                : "Sin configurar"
        }
        return config.isEnabled ? "Activo" : "Desactivado"
    }

    // MARK: - Picker

    @ViewBuilder
    private var pickerContent: some View {
        Text("Elige un proveedor")
            .font(.subheadline.weight(.medium))

        ForEach(SubtitleProviderCatalog.addable) { descriptor in
            let alreadyAdded = configs.contains { $0.id == descriptor.id }
            Button {
                mode = .editing(descriptor.id, isNew: true)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(descriptor.displayName)
                            .font(.subheadline.weight(.medium))
                        Text(descriptor.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if alreadyAdded {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(MareaTheme.Colors.accent)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(alreadyAdded)
        }

        Button("Cancelar") { mode = .list }
            .font(.caption)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
    }

    // MARK: - Data

    private func reload() {
        configs = store.effectiveConfigs()
    }
}
#endif
