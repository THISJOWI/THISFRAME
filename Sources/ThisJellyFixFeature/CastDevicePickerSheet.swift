import SwiftUI
import ThisJellyFixCore

#if os(iOS)
import ThisJellyFixCast

/// Selector de dispositivos Cast — la hoja que aparece al pulsar el botón.
///
/// Lista SOLO dispositivos reales descubiertos por el SDK (GCKDiscoveryManager);
/// sin sesión muestra el estado del escaneo, con sesión ofrece desconectar.
/// Sigue el design system de La Marea (superficie glass, acento, tipografía).
struct CastDevicePickerSheet: View {
    @ObservedObject var controller = CastController.shared
    @Environment(\.dismiss) private var dismiss

    @State private var connectingId: String?
    /// Turns the neutral empty state into a diagnostic hint after the scan
    /// has had time to find devices (~6 s).
    @State private var hasScanTimedOut = false
    @State private var scanTimeoutTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MareaTheme.Colors.borderGlow)
            content
        }
        .background(MareaTheme.Colors.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            controller.startDiscovery()
            hasScanTimedOut = false
            scanTimeoutTask = makeScanTimeoutTask()
        }
        // The scan stays running when the sheet closes (startDiscovery is
        // idempotent and cheap): stopping here meant every re-open began
        // from zero — the first seconds showed "Sin dispositivos" even with
        // devices already on the network, the classic "no lo detecta".
        // Detection hints live in the empty state (local-network permission).
        .onDisappear { scanTimeoutTask?.cancel() }
    }

    /// Flags the empty state as "scan finished with nothing found" so the
    /// local-network permission hint can be shown instead of a neutral copy.
    private func makeScanTimeoutTask() -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            hasScanTimedOut = true
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transmitir a")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if controller.manager.state.isConnected {
                Button {
                    controller.disconnect()
                    dismiss()
                } label: {
                    Text("Desconectar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MareaTheme.Colors.accentText)
                }
            }
        }
        .padding(MareaTheme.Spacing.md)
    }

    private var subtitle: String {
        switch controller.manager.state.phase {
        case .connected(let name): return "Conectado a \(name)"
        case .connecting(let name): return "Conectando con \(name)…"
        case .discovering: return "Buscando dispositivos…"
        case .failed(let reason): return reason
        case .idle: return "Elige un dispositivo de tu red"
        }
    }

    @ViewBuilder
    private var content: some View {
        if controller.devices.isEmpty {
            emptyState
        } else {
            deviceList
        }
    }

    private var emptyState: some View {
        VStack(spacing: MareaTheme.Spacing.md) {
            Spacer()
            CastIcon()
                .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 56, height: 42)
            Text(hasScanTimedOut ? "No se encontraron dispositivos" : "Buscando dispositivos…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // After ~6 s a healthy scan has found the Chromecasts. If it
            // found none the usual culprit is the local-network permission
            // (iOS silently denies Bonjour → the SDK sees zero devices).
            if hasScanTimedOut {
                Text("""
                ¿El Chromecast está encendido y en la misma red que este \
                iPhone? Si ya le diste permiso, revisa \
                Ajustes → Privacidad → Red local.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MareaTheme.Spacing.lg)
            } else {
                Text("¿Tu Chromecast está encendido y en la misma red que este iPhone?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MareaTheme.Spacing.lg)
            }
            Button {
                hasScanTimedOut = false
                scanTimeoutTask?.cancel()
                controller.restartDiscovery()
                scanTimeoutTask = makeScanTimeoutTask()
            } label: {
                Label("Reintentar", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, MareaTheme.Spacing.md)
                    .padding(.vertical, MareaTheme.Spacing.sm)
                    .background(MareaTheme.Colors.surfaceElevated, in: Capsule())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var deviceList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(controller.devices) { device in
                    deviceRow(device)
                }
            }
            .padding(.vertical, MareaTheme.Spacing.sm)
        }
    }

    private func deviceRow(_ device: CastDevice) -> some View {
        Button {
            connectingId = device.id
            controller.connect(to: device)
        } label: {
            HStack(spacing: MareaTheme.Spacing.md) {
                CastIcon()
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 28, height: 21)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if device.isBusy {
                        Text("En uso — conectar tomará el control")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isConnected(device) {
                    Text("Conectado")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MareaTheme.Colors.accentText)
                } else if isConnecting(device) {
                    ProgressView().tint(Color.primary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, MareaTheme.Spacing.md)
            .padding(.vertical, 12)
            .background(
                isConnected(device) ? MareaTheme.Colors.surfaceElevated : Color.clear,
                in: RoundedRectangle(cornerRadius: MareaTheme.Radius.small)
            )
        }
        .disabled(controller.manager.state.isConnecting)
    }

    private func isConnected(_ device: CastDevice) -> Bool {
        if case .connected(let name) = controller.manager.state.phase { return name == device.name }
        return false
    }

    private func isConnecting(_ device: CastDevice) -> Bool {
        connectingId == device.id && controller.manager.state.isConnecting
    }
}
#endif
