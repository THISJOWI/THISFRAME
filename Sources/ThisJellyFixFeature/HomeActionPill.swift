import SwiftUI
import ThisJellyFixCore
#if os(iOS)
import ThisJellyFixCast
#endif

/// Home action pill: profile avatar + transmit entry (+ downloads when available).
struct HomeActionPill: View {
    var discovery: DiscoveryModel?
    var userName: String = ""
    var serverURL: URL? = nil
    var token: String? = nil
    var userId: String? = nil
    var onLogout: () -> Void = {}

    @State private var showCastPicker = false
    @State private var showProfile = false
    #if os(iOS)
    @ObservedObject private var cast = CastController.shared
    #endif

    private var avatarURL: URL? {
        guard let serverURL, let userId, let token, !token.isEmpty else { return nil }
        return serverURL
            .appendingPathComponent("Users/\(userId)/Images/Primary")
            .appending(queryItems: [URLQueryItem(name: "api_key", value: token)])
    }

    var body: some View {
        HStack(spacing: 4) {
            #if os(iOS)
            Button {
                showCastPicker = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    CastIcon()
                        .foregroundStyle(MareaTheme.Colors.crimsonFrame)
                        .frame(width: 24, height: 18)
                        .overlay(CastIcon().stroke(MareaTheme.Colors.crimsonFrame, style: StrokeStyle(lineWidth: 2, lineCap: .round)))
                        .frame(width: 34, height: 34)
                    if cast.manager.state.isConnected {
                        Circle()
                            .fill(MareaTheme.Colors.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: -3, y: -3)
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

            // Profile button directly beside the transmit icon
            Button {
                showProfile = true
            } label: {
                ZStack {
                    Circle()
                        .fill(MareaTheme.Colors.accent.opacity(0.2))
                        .frame(width: 26, height: 26)
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            if !userName.isEmpty {
                                Text(String(userName.prefix(1)).uppercased())
                                    .font(.caption2.bold())
                                    .foregroundStyle(MareaTheme.Colors.accentText)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(MareaTheme.Colors.accent)
                            }
                        }
                    }
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Perfil de \(userName)")
            .sheet(isPresented: $showProfile) {
                ProfileSettingsView(
                    userName: userName,
                    onLogout: onLogout,
                    serverURL: serverURL,
                    token: token,
                    userId: userId
                )
            }
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
