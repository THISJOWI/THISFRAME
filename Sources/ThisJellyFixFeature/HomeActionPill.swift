import SwiftUI
import ThisJellyFixCore
#if os(iOS)
import ThisJellyFixCast
#endif

/// Home action pill (P8): profile access + gear settings + transmit entry
/// (+ downloads when a download service exists). Every destination is reused
/// — no new flows, no Cast re-implementation: the transmit button only opens
/// the existing device picker.
struct HomeActionPill: View {
    let userName: String
    let serverURL: URL
    let token: String
    let userId: String
    let onLogout: () -> Void
    var discovery: DiscoveryModel?

    @State private var showCastPicker = false
    #if os(iOS)
    @ObservedObject private var cast = CastController.shared
    #endif

    var body: some View {
        HStack(spacing: 2) {
            NavigationLink(
                destination: ProfileView(
                    userName: userName,
                    onLogout: onLogout,
                    serverURL: serverURL,
                    token: token,
                    userId: userId
                )
            ) {
                Image(systemName: "person.fill")
                    .pillIcon()
            }
            .accessibilityLabel("Perfil")

            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape.fill")
                    .pillIcon()
            }
            .accessibilityLabel("Ajustes")

            #if os(iOS)
            Button {
                showCastPicker = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    CastIcon()
                        .stroke(.white, lineWidth: 0)
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 15)
                        .overlay(CastIcon().stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round)))
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
        .background(.white.opacity(0.08), in: Capsule())
    }
}

private extension View {
    func pillIcon() -> some View {
        self
            .font(.body)
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
    }
}
