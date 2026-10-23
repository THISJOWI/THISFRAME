import SwiftUI
import ThisJellyFixCore
#if os(iOS)
import ThisJellyFixCast
#endif

/// Home action pill (P8): gear settings + transmit entry (+ downloads when
/// a download service exists). Every destination is reused — no new flows,
/// no Cast re-implementation: the transmit button only opens the existing
/// device picker. Profile lives in its own tab, so the pill carries no
/// profile button.
struct HomeActionPill: View {
    var discovery: DiscoveryModel?

    @State private var showCastPicker = false
    #if os(iOS)
    @ObservedObject private var cast = CastController.shared
    #endif

    var body: some View {
        HStack(spacing: 2) {
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape.fill")
                    .pillIcon()
                    .foregroundStyle(MareaTheme.Colors.crimsonFrame)
            }
            .accessibilityLabel("Ajustes")

            #if os(iOS)
            Button {
                showCastPicker = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    CastIcon()
                        .foregroundStyle(MareaTheme.Colors.crimsonFrame)
                        .frame(width: 20, height: 15)
                        .overlay(CastIcon().stroke(MareaTheme.Colors.crimsonFrame, style: StrokeStyle(lineWidth: 2, lineCap: .round)))
                        .frame(width: 36, height: 36)
                    if cast.manager.state.isConnected {
                        Circle()
                            .fill(MareaTheme.Colors.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: -4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Transmitir")
            .sheet(isPresented: $showCastPicker) {
                CastDevicePickerSheet()
            }
            #endif

            #if os(iOS) || os(macOS)
            if let discovery, discovery.hasDownloadService {
                DownloadsButton(discovery: discovery)
            }
            #endif
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .pillGlassBackground()
    }
}

/// Liquid Glass (OS 26+) con fallback translúcido en versiones anteriores.
///
/// visionOS has no Liquid Glass API — it keeps the translucent fallback even
/// on OS 26.
private extension View {
    @ViewBuilder
    func pillGlassBackground() -> some View {
        #if os(visionOS)
        self.background(MareaTheme.Colors.glass, in: Capsule())
        #else
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(MareaTheme.Colors.glass, in: Capsule())
        }
        #endif
    }
}

private extension View {
    func pillIcon() -> some View {
        self
            .font(.body)
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
    }
}
