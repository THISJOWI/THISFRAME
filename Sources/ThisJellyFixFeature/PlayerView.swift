import SwiftUI
import ThisJellyFixCore
import ThisJellyFixPlayback
import AVKit
#if os(iOS)
import AVFoundation
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Why the fullscreen player is being torn down.
///
/// Parents (DetailView, DirectPlayer) unmount `PlayerView` themselves when a
/// stream fails, and they cannot reach its view model. They set this flag
/// synchronously right before removing the player; `onDisappear` consumes it
/// at disappearance time. A plain `Bool` parameter would NOT work: SwiftUI
/// coalesces the error write and the unmount into a single render, so the view
/// would still carry the pre-error value and hand a broken episode off to PiP
/// (floating window over the error screen + ghost audio).
enum PlayerTeardown {
    nonisolated(unsafe) private static var errorFlag = false

    /// The parent is removing the player BECAUSE of a failure.
    static func noteError() { errorFlag = true }
    /// A new playback session starts — drop anything a previous one left.
    static func reset() { errorFlag = false }
    /// Returns the flag and clears it (every read consumes).
    static func consumeErrorFlag() -> Bool {
        defer { errorFlag = false }
        return errorFlag
    }
}

struct PlayerView: View {
    let streamURL: URL
    let title: String
    var allowStop: Bool = true
    var startPosition: Double? = nil
    var onDismiss: (() -> Void)?
    // Playback reporting (optional — if nil, reporting is skipped)
    var itemId: String? = nil
    var serverURL: URL? = nil
    var token: String? = nil
    var userId: String? = nil
    /// Jellyfin media type of the playing item ("Movie", "Episode", …) —
    /// carried into the Handoff payload so the receiver knows what it is.
    var mediaType: String = ""
    var playSessionId: String? = nil
    // Server media streams — needed to load external subtitle files
    var mediaStreams: [MediaStream] = []
    /// Audio SERVIDO (`MediaStream.index` pedido o default): el picker lo
    /// usa para mapear engine↔servidor. Llega en render separado de
    /// `mediaStreams`/`streamURL` (ver onChange): nunca adivinar por idioma.
    var audioServerIndex: Int? = nil
    // Next episode wiring — when provided, the credits overlay offers it
    var nextEpisode: JellyfinEpisode? = nil
    var onPlayNextEpisode: ((JellyfinEpisode) -> Void)? = nil
    // Previous episode wiring — when provided, transport ⏮ offers it
    var previousEpisode: JellyfinEpisode? = nil
    var onPlayPreviousEpisode: ((JellyfinEpisode) -> Void)? = nil
    /// Series name shown under the episode/movie title in the controls.
    var subtitle: String? = nil
    /// true when this playback session started from a received handoff
    /// continuation: the receiver must never yield back to the sender's
    /// still-active session (both devices would stop otherwise).
    var receivedViaHandoff: Bool = false
    #if os(iOS)
    /// The floating PiP session's live view model: restore hands it back so
    /// playback continues uninterrupted (same AVPlayer — no re-prepare, no
    /// re-buffer). nil = fresh playback session.
    var restoredViewModel: PlayerViewModel? = nil
    #endif

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PlayerViewModel
    @State private var seekIndicator: SeekIndicator?
    @State private var controlsTimer: Timer?
    @State private var wasPlaying = false
    /// The system route sheet is on screen: the host view must not unmount
    /// (dead picker) and control toggles must not race its presentation.
    @State private var isRouteSheetPresenting = false
    /// In-flight playback work. Untracked tasks kept running after the player
    /// was dismissed and called `engine.play()` on a stopped engine — audio with
    /// no UI. Cancelled in `onDisappear`.
    @State private var playbackTask: Task<Void, Never>?
    @State private var episodeSwapTask: Task<Void, Never>?

    /// Subtitle size preference (UserDefaults key from SubtitleSizeSettings).
    /// @AppStorage watches UserDefaults live — the overlay updates the moment
    /// the user changes it in Settings without restarting playback.
    @AppStorage(SubtitleSizeSettings.Key.relativeSize) private var subtitleSizeRaw: Double = 1.0

    private var subtitleFontSize: CGFloat {
        let base: CGFloat = 17
        let multiplier = SubtitleSizeSettings.RelativeSize(rawValue: subtitleSizeRaw)?.rawValue ?? 1.0
        return base * multiplier
    }

    // MARK: - Fit / fill pinch
    @State private var isPinching = false
    @State private var lastPinchEnd: Date = .distantPast
    #if os(iOS)
    /// Fullscreen players currently on screen. The root's restore handler
    /// consults it so a restore can never present a SECOND player over a
    /// cover that already owns the UI (presentation fails silently and the
    /// floating window dies with nothing playing).
    nonisolated(unsafe) static var presentedCount = 0
    #endif

    init(
        streamURL: URL,
        title: String,
        allowStop: Bool = true,
        startPosition: Double? = nil,
        onDismiss: (() -> Void)? = nil,
        itemId: String? = nil,
        serverURL: URL? = nil,
        token: String? = nil,
        userId: String? = nil,
        mediaType: String = "",
        playSessionId: String? = nil,
        mediaStreams: [MediaStream] = [],
        audioServerIndex: Int? = nil,
        nextEpisode: JellyfinEpisode? = nil,
        onPlayNextEpisode: ((JellyfinEpisode) -> Void)? = nil,
        previousEpisode: JellyfinEpisode? = nil,
        onPlayPreviousEpisode: ((JellyfinEpisode) -> Void)? = nil,
        subtitle: String? = nil,
        receivedViaHandoff: Bool = false,
        restoredViewModel: PlayerViewModel? = nil
    ) {
        self.streamURL = streamURL
        self.title = title
        self.allowStop = allowStop
        self.startPosition = startPosition
        self.onDismiss = onDismiss
        self.itemId = itemId
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        self.mediaType = mediaType
        self.playSessionId = playSessionId
        self.mediaStreams = mediaStreams
        self.audioServerIndex = audioServerIndex
        self.nextEpisode = nextEpisode
        self.onPlayNextEpisode = onPlayNextEpisode
        self.previousEpisode = previousEpisode
        self.onPlayPreviousEpisode = onPlayPreviousEpisode
        self.subtitle = subtitle
        self.receivedViaHandoff = receivedViaHandoff
        #if os(iOS)
        self.restoredViewModel = restoredViewModel
        _viewModel = State(initialValue: restoredViewModel ?? PlayerViewModel())
        #else
        _viewModel = State(initialValue: PlayerViewModel())
        #endif
    }

    /// Restore-from-PiP mount: the item is already playing in the adopted VM.
    private var isRestoring: Bool {
        #if os(iOS)
        restoredViewModel != nil
        #else
        false
        #endif
    }

    private func dismissPlayer() {
        onDismiss?() ?? dismiss()
    }

    /// Wire the CURRENT item into the view model: reporting, server streams and
    /// PiP prefetch. Called once, when the player mounts.
    private func configureEpisode() {
        // A restored (floating) VM keeps its own flag — only a fresh mount
        // adopts the view's handoff provenance.
        if !isRestoring {
            viewModel.receivedViaHandoff = receivedViaHandoff
        }
        if let itemId, let serverURL, let token, let userId {
            viewModel.configureReporting(userId: userId, serverURL: serverURL, token: token, itemId: itemId, playSessionId: playSessionId)
        } else {
            TJFLog("onAppear: reporting NOT configured itemId=\(itemId != nil) serverURL=\(serverURL != nil) token=\(token != nil) userId=\(userId != nil)")
        }
        viewModel.configureMediaStreams(mediaStreams)
        viewModel.noteServedAudioServerIndex(audioServerIndex)
        viewModel.configureNowPlaying(title: title)
        wireNextEpisode()
        // Server favorite flag for the heart button (fills in when it lands).
        Task { await viewModel.loadFavoriteState() }
    }

    /// Credits overlay action for the CURRENT next episode (re-run whenever
    /// `nextEpisode` changes, including after a swap). Wires ⏮ the same way.
    private func wireNextEpisode() {
        if let nextEpisode, let onPlayNextEpisode {
            viewModel.hasNextEpisode = true
            viewModel.onPlayNextEpisode = { onPlayNextEpisode(nextEpisode) }
        } else {
            viewModel.hasNextEpisode = false
            viewModel.onPlayNextEpisode = nil
        }
        if let previousEpisode, let onPlayPreviousEpisode {
            viewModel.hasPreviousEpisode = true
            viewModel.onPlayPreviousEpisode = { onPlayPreviousEpisode(previousEpisode) }
        } else {
            viewModel.hasPreviousEpisode = false
            viewModel.onPlayPreviousEpisode = nil
        }
    }

    /// Fills the Handoff activity for an active playback session. Kept out of
    /// `body`'s closure: the whole expression made the type-checker blow its
    /// per-expression budget once the controls overlay grew.
    private func configurePlayingActivity(_ activity: NSUserActivity) {
        guard let itemId, let serverURL, let userId else { return }
        let handoffItem = HandoffMediaItem(id: itemId, name: title, type: mediaType)
        let built: NSUserActivity = HandoffActivity.playingActivity(
            item: handoffItem,
            serverURL: serverURL,
            userId: userId,
            position: viewModel.currentTime
        )
        activity.title              = built.title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch  = false
        activity.userInfo           = built.userInfo
        // M3: the closure configures a DIFFERENT activity instance than
        // `built` — these two must be copied too, or the continuation
        // never routes to the right scene / gets its userInfo stripped.
        activity.requiredUserInfoKeys  = built.requiredUserInfoKeys
        activity.targetContentIdentifier = built.targetContentIdentifier
    }

    /// Open the media and start playback for the first mount.
    private func startPlayback() {
        playbackTask = Task {
            await viewModel.prepareStream(url: streamURL, startPosition: startPosition)
            // AVPlayer presents the layer itself — no drawable to attach, no
            // warm/resolve chain (native PiP uses the same AVPlayerLayer).
            guard !Task.isCancelled else { return }
            await viewModel.togglePlayPause()
            // Resume from saved position — the media opens at 0, so seek
            // explicitly after play() (AVPlayer cannot seek on a nil item).
            if let start = startPosition, start > 0 {
                await viewModel.seek(to: start)
            }
            guard !Task.isCancelled else { return }
        }
    }

    /// In-player cover for the black loading gap while an episode swap runs.
    @ViewBuilder
    private var episodeSwapCover: some View {
        if viewModel.isSwitchingEpisode {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text(title.isEmpty ? "Cargando…" : title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Siguiente episodio")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Full controls overlay, mounted only while shown.
    @ViewBuilder
    /// Controls are ALWAYS mounted and hidden with opacity instead of being
    /// torn out of the tree. Two reasons: the AirPlay route picker must never
    /// unmount (remounting it leaves the system sheet dead — later taps do
    /// nothing and the receiver list re-prompts), and the fade in/out stays a
    /// pure opacity animation. Hidden = no hit testing, so taps fall through
    /// to the video's tap catcher below.
    private var controlsOverlay: some View {
        ControlsOverlay(
            title: title,
            subtitle: subtitle,
            viewModel: viewModel,
            onDismiss: { dismissPlayer() },
            onToggleFullscreen: {
                #if os(macOS)
                if let nsWindow = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isKeyWindow }) {
                    nsWindow.toggleFullScreen(nil)
                }
                #endif
            },
            onAirPlayPresenting: onAirPlayPresenting
        )
        .opacity(viewModel.showControls ? 1 : 0)
        .allowsHitTesting(viewModel.showControls)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showControls)
    }

    var body: some View {
        // Use .overlay() instead of ZStack so ControlsOverlay is always the
        // topmost AppKit hosting view — critical after toggleFullScreen restructures
        // the window hierarchy and can reorder ZStack children.
        // Fit/fill is applied on the layer (videoGravity): no SwiftUI
        // scaleEffect, so native embedded subtitles are never cropped.
        PlayerLayerBridge(viewModel: viewModel)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())

            // Episode swap — the player stays mounted, so cover the black
            // loading gap with an in-player indicator instead of dropping back
            // out to the episode list.
            // NOTE: an active PiP session's AVPlayerLayer is hosted by
            // ThisJellyFixRootView (always alive) — hosting it here would rip
            // the layer out of the hierarchy the moment this cover closes.
            .overlay { episodeSwapCover }

            // Tap catcher — below controls, above video
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        // Double-tap: toggle fit ↔ fill
                        viewModel.setFill(!viewModel.isFill)
                    }
                    .onTapGesture {
                        // The old A6 guard (`guard !isRouteSheetPresenting`)
                        // bricked EVERY tap when the system skipped
                        // routePickerViewDidEndPresentingRoutes — flag stuck
                        // true, app "pillada". The route sheet is modal (its
                        // own UI swallows touches), so the guard never
                        // protected anything reachable; the auto-hide freeze
                        // in onAirPlayPresenting is what keeps the host view
                        // alive mid-presentation. Taps stay live regardless.
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showControls.toggle()
                        }
                        if viewModel.showControls {
                            resetControlsTimer()
                        } else {
                            controlsTimer?.invalidate()
                        }
                    }
            }

            // Subtitles with dark background (single renderer).
            // Native AVPlayer legible rendering is permanently disabled to eliminate duplicate un-backgrounded text.
            .overlay(alignment: .bottom) {
                if let text = viewModel.subtitleText {
                    Text(text)
                        .font(.system(size: subtitleFontSize, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.bottom, viewModel.showControls ? 150 : 40)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }

            // Controls overlay — always the topmost hosting view. AirPlay's
            // route picker lives INSIDE it (top-right cluster slot), mounted
            // for the cluster's lifetime; while the system sheet is up,
            // `onAirPlayPresenting` keeps the controls from hiding.
            .overlay { controlsOverlay }

            // Seek HUD
            .overlay {
                if let seek = seekIndicator {
                    SeekHUD(text: seek.text)
                        .transition(.opacity)
                }
            }

            // AirPlay status: active (green transmitting), connecting
            // (transport blocked) or last failure (tappable to dismiss).
            .overlay(alignment: .top) {
                #if !os(visionOS)
                if viewModel.isAirPlayActive {
                    Label("Transmitiendo por AirPlay", systemImage: "airplayvideo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.green.opacity(0.7), in: Capsule())
                        .padding(.top, 56)
                        .transition(.opacity)
                } else if viewModel.isAirPlayConnecting {                    Label("Conectando AirPlay…", systemImage: "airplayvideo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(.top, 56)
                        .transition(.opacity)
                } else if let message = viewModel.airplayMessage {
                    Button {
                        viewModel.dismissAirPlayMessage()
                    } label: {
                        Label("\(message) — tocar para cerrar", systemImage: "airplay.exclamationmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.75), in: Capsule())
                            .padding(.top, 56)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                if let favError = viewModel.favoriteError {
                    Button {
                        viewModel.dismissFavoriteError()
                    } label: {
                        Label("\(favError) — tocar para cerrar", systemImage: "heart.slash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.75), in: Capsule())
                            .padding(.top, viewModel.airplayMessage != nil ? 100 : 56)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                #endif
                #if os(iOS)
                // Cast: emitiendo (con nombre del dispositivo) o error.
                // Muestra SIEMPRE la salida activa — impide que el usuario
                // crea que sigue viendo en el iPhone cuando no es así.
                if viewModel.isCastEmitting,
                   let name = viewModel.castController?.sessionState.lastDeviceName {
                    Label("Transmitiendo a \(name)", systemImage: "tv.badge.waveform")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(.top, viewModel.isAirPlayConnecting ? 100 : 56)
                        .transition(.opacity)
                } else if let message = viewModel.castMessage {
                    Label(message, systemImage: "tv.badge.exclamationmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.75), in: Capsule())
                        .padding(.top, 56)
                        .transition(.opacity)
                }
                #endif
            }

            // Seek/buffering feedback — the transport is working even though
            // the picture hasn't caught up yet.
            .overlay {
                if viewModel.isSeeking {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .transition(.opacity)
                }
            }

            // Skip segment overlay (intro / recap / credits) — visible even
            // when the controls are hidden, like Netflix's skip button.
            .overlay(alignment: .bottomTrailing) {
                if let segment = viewModel.activeSegment {
                    SkipSegmentOverlay(
                        segment: segment,
                        countdown: viewModel.segmentCountdown,
                        hasNextEpisode: viewModel.hasNextEpisode,
                        onSkip: { viewModel.skipActiveSegment() },
                        onPlayNext: { viewModel.playNextEpisode() }
                    )
                    .transition(.opacity)
                    .padding(.trailing, 24)
                    .padding(.bottom, viewModel.showControls ? 140 : 32)
                }
            }

            // Error message
            .overlay {
                if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                        Button("Cerrar") { dismissPlayer() }
                            .buttonStyle(.borderedProminent)
                            .tint(MareaTheme.Colors.accent)
                    }
                }
            }

            // Handoff takeover: another device took the item — the engine is
            // already stopped, this screen goes dark and says who took over.
            .overlay {
                if let taker = viewModel.handoffTakeoverDeviceName {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        VStack(spacing: 14) {
                            Image(systemName: "rectangle.on.rectangle.slash")
                                .font(.system(size: 44))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("La reproducción continuó en \(taker)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text("Este dispositivo se ha detenido.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                            Button("Cerrar") { dismissPlayer() }
                                .buttonStyle(.borderedProminent)
                                .tint(MareaTheme.Colors.accent)
                        }
                        .padding(32)
                    }
                    .transition(.opacity)
                }
            }

            // macOS: separate floating window for close button.
            // toggleFullScreen restructures the view hierarchy and SwiftUI overlay
            // buttons lose hit testing. A separate NSWindow bypasses this entirely.
            #if os(macOS)
            .overlay {
                CloseButtonWindowRepresentable(
                    isVisible: viewModel.showControls,
                    onClose: { dismissPlayer() }
                )
                .allowsHitTesting(false)
            }
            #endif

            .onKeyPress(.escape) {
                dismissPlayer()
                return .handled
            }
            #if os(tvOS)
            // E8: tvOS has no close control — the Menu button was a dead end.
            .onExitCommand { dismissPlayer() }
            #endif
            #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard !isPinching, Date().timeIntervalSince(lastPinchEnd) >= 0.4 else { return }
                        handleSwipe(value)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in handleMagnifyChanged(value) }
                    .onEnded { value in handleMagnifyEnded(value) }
            )
            #endif
        .onAppear {
            #if os(iOS)
            // Force landscape orientation for playback
            forceLandscape()
            // Closing PiP (X) while floating dismisses this fullscreen UI.
            viewModel.onPiPClosed = { dismissPlayer() }
            viewModel.playbackTitle = title
            // Restore/close observers for THIS mount — detached on disappear.
            viewModel.attachPipHandlers()
            Self.presentedCount += 1
            if isRestoring {
                // Adopted the floating VM: its engine already plays and its
                // reporting is configured — release the session so the root
                // stops hosting the layer (this bridge takes it over).
                PipCoordinator.shared.releaseFloating()
            }
            #endif
            PlayerTeardown.reset()
            configureEpisode()
            // Start the track/report timer FIRST — before any async work — so a
            // slow stream prepare can never leave us without polls.
            viewModel.startUpdating()
            // Restored sessions are already playing at their position: a second
            // prepareStream would tear down the item the PiP window just closed.
            if !isRestoring {
                startPlayback()
            }
            resetControlsTimer()
        }
        .onChange(of: streamURL) { _, newURL in
            // Episode swap: stay mounted and hand the engine the new stream — the
            // player never drops back out to the episode list.
            wireNextEpisode()
            // A fast double-swap must not stack concurrent prepares: the
            // older task is cancelled and its async subtitle loads are
            // generation-guarded inside the view model.
            episodeSwapTask?.cancel()
            episodeSwapTask = Task {
                await viewModel.switchToEpisode(
                    url: newURL,
                    startPosition: startPosition,
                    itemId: itemId,
                    serverURL: serverURL,
                    token: token,
                    userId: userId,
                    playSessionId: playSessionId,
                    mediaStreams: mediaStreams,
                    audioServerIndex: audioServerIndex
                )
            }
        }
        .onChange(of: audioServerIndex) { _, _ in
            // Índice servido tardío (mismo caso que `mediaStreams`): solo
            // registra, sin tocar playback (el stream ya es ese).
            viewModel.noteServedAudioServerIndex(audioServerIndex)
        }
        .onChange(of: itemId) { _, _ in
            // `streamURL` and `mediaStreams`/`itemId` update in separate
            // render passes (DetailView/DirectPlayer set them sequentially):
            // the streamURL swap above may have run with the PREVIOUS
            // episode's streams. Re-sync late-arriving props without
            // touching playback.
            viewModel.refreshMediaStreams(mediaStreams)
        }
        .onChange(of: mediaStreams) { _, _ in
            viewModel.refreshMediaStreams(mediaStreams)
        }
        .onChange(of: nextEpisode) { _, _ in
            // The credits list can resolve AFTER mount — keep the overlay wired.
            wireNextEpisode()
        }
        .onDisappear {
            #if os(iOS)
            // Restore auto-rotation when leaving player
            restoreOrientation()
            // This mount's PiP observers are dead weight now — the root view
            // keeps its own permanent pair for restore/close.
            viewModel.detachPipHandlers()
            Self.presentedCount = max(0, Self.presentedCount - 1)
            #endif
            // Drop any playback work still in flight BEFORE stopping: a task
            // resuming after teardown would call play()/seek() on a dead engine.
            playbackTask?.cancel()
            playbackTask = nil
            episodeSwapTask?.cancel()
            episodeSwapTask = nil
            controlsTimer?.invalidate()
            viewModel.stopUpdating()
            if allowStop {
                // Leaving the player must NOT cut playback: handleViewExit
                // hands the running item to the floating PiP window when
                // possible and only stops the engine when nothing can carry it.
                // Read the teardown reason AT disappearance time: a plain Bool
                // parameter would carry the value of the last render, which
                // pre-dates a failure written in the same update (SwiftUI
                // coalesces them) — that is how a failed swap still handed
                // playback off to PiP over the error screen.
                viewModel.handleViewExit(handoffAllowed: !PlayerTeardown.consumeErrorFlag())
            }
        }
        .onChange(of: viewModel.isPlaying) { _, playing in
            // Show controls when playback pauses/stops unexpectedly (buffering, error)
            if wasPlaying && !playing {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showControls = true
                }
                resetControlsTimer()
            }
            wasPlaying = playing
        }
        // Handoff: publish the current playback state so the user can resume on
        // another Apple device. Only published when we have a full session
        // (itemId + serverURL + userId present); the token is deliberately
        // omitted — the receiving device reads its own from the shared Keychain.
        .userActivity(
            HandoffActivity.playing,
            isActive: itemId != nil && serverURL != nil && userId != nil
                // F3: never advertise `playing` while the center says another
                // owner holds the slot — a desync would otherwise publish
                // detail/browsing AND playing simultaneously.
                && HandoffCenter.shared.isPlaybackActive
        ) { activity in
            configurePlayingActivity(activity)
        }
        // m5: while this view is gone (PiP float window) NO player advertises
        // `playing` — with the center still holding Handoff, zero activities
        // were announced. Hand it back to browsing; the restored player
        // re-claims it in configureNowPlaying.
        .onDisappear {
            HandoffCenter.shared.setPlaybackActive(false)
        }
        .sheet(isPresented: $viewModel.showAudioPicker) {
            AudioPickerSheet(
                tracks: viewModel.availableAudioTracks,
                selected: viewModel.selectedAudioTrackIndex
            ) { track in
                Task { await viewModel.selectAudioTrack(track) }
            }
        }
        .sheet(isPresented: $viewModel.showSubtitlePicker) {
            SubtitlePickerSheet(viewModel: viewModel) { track in
                Task { await viewModel.selectSubtitleTrack(track) }
            }
        }
        .sheet(isPresented: $viewModel.showSpeedPicker) {
            SpeedPickerSheet(
                currentRate: viewModel.playbackRate
            ) { rate in
                Task { await viewModel.setPlaybackRate(rate) }
            }
        }
        .sheet(isPresented: $viewModel.showQualityPicker) {
            QualityPickerSheet(
                current: viewModel.selectedQuality
            ) { quality in
                Task { await viewModel.switchQuality(quality) }
            }
        }
        #if os(iOS)
        .modifier(CastPickerSheetModifier(viewModel: viewModel))
        #endif
    }

    // MARK: - Fit / fill gestures

    #if !os(tvOS)
    /// Pinch out → fill the whole screen (crop overflow).
    /// Pinch in → fit the whole video (letterbox, no crop).
    private func handleMagnifyChanged(_ value: MagnifyGesture.Value) {
        isPinching = true
        let fill = value.magnification >= 1
        if viewModel.isFill != fill {
            viewModel.setFill(fill)
        }
    }

    private func handleMagnifyEnded(_ value: MagnifyGesture.Value) {
        isPinching = false
        lastPinchEnd = Date()
        viewModel.setFill(value.magnification >= 1)
    }

    private func handleSwipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height

        if abs(horizontal) > abs(vertical) {
            let delta = horizontal > 0 ? 15.0 : -15.0
            Task {
                await viewModel.seekRelative(delta)
                withAnimation { seekIndicator = SeekIndicator(text: delta > 0 ? "+15s" : "-15s") }
                try? await Task.sleep(for: .seconds(0.8))
                withAnimation { seekIndicator = nil }
            }
        }
    }
    #endif

    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.showControls = false
                }
            }
        }
    }

    /// AirPlay route sheet presentation state — the picker is mounted for
    /// the player's whole lifetime now, so this no longer guards against
    /// unmounting; it still freezes the controls auto-hide while the
    /// system sheet is up and re-arms it when the sheet closes.
    private func onAirPlayPresenting(_ presenting: Bool) {
        isRouteSheetPresenting = presenting
        if presenting {
            controlsTimer?.invalidate()
            viewModel.showControls = true
        } else if viewModel.showControls {
            resetControlsTimer()
        }
    }

    #if os(iOS)
    private func forceLandscape() {
        // Lock to landscape FIRST — supportedInterfaceOrientationsFor returns this,
        // forcing iOS to rotate away from portrait.
        UIApplication.shared.tjf_orientationLock = [.landscapeLeft, .landscapeRight]

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            .first

            // Supported API only: the old UIDevice.setValue(_, forKey:
            // "orientation") KVC hack is rejected (E17) — geometry update +
            // rotation re-evaluation is the sanctioned path.
            if let windowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            UINavigationController.attemptRotationToDeviceOrientation()
        }
    }

    private func restoreOrientation() {
        // Unlock immediately
        UIApplication.shared.tjf_orientationLock = .all

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            UINavigationController.attemptRotationToDeviceOrientation()
        }

        // Safety: ensure unlocked after transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIApplication.shared.tjf_orientationLock = .all
        }
    }
    #endif
}

#if os(iOS)
// MARK: - Orientation Lock

extension UIApplication {
    private struct Keys {
        static var orientationLock: UInt8 = 0
    }

    public var tjf_orientationLock: UIInterfaceOrientationMask {
        get {
            (objc_getAssociatedObject(self, &Keys.orientationLock) as? UIInterfaceOrientationMask) ?? .all
        }
        set {
            objc_setAssociatedObject(self, &Keys.orientationLock, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// App Delegate must implement this to support orientation lock:
// func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
//     return orientationLock
// }
#endif

// MARK: - AVPlayer Layer Bridge (Cross-platform)

// The engine owns one AVPlayerLayer; these containers only parent it while a
// fullscreen mount exists. CALayers never intercept pointer events, so no
// hit-testing pass-through tricks are needed (that was a VLC drawable thing).

#if os(macOS)
private struct PlayerLayerBridge: NSViewRepresentable {
    let viewModel: PlayerViewModel

    func makeNSView(context: Context) -> PlayerLayerContainer {
        PlayerLayerContainer()
    }

    func updateNSView(_ nsView: PlayerLayerContainer, context: Context) {
        nsView.host(viewModel.engine.renderingLayer)
    }
}

private class PlayerLayerContainer: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil so ALL mouse events pass through to SwiftUI views on top.
        nil
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.forEach { $0.frame = bounds }
    }

    func host(_ layer: CALayer?) {
        guard let layer else { return }
        if layer.superlayer !== self.layer {
            layer.removeFromSuperlayer()
            self.layer?.addSublayer(layer)
        }
        layer.frame = bounds
    }
}
#else
private struct PlayerLayerBridge: UIViewRepresentable {
    let viewModel: PlayerViewModel

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        PlayerLayerContainerView()
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        uiView.host(viewModel.engine.renderingLayer)
    }
}

private class PlayerLayerContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.forEach { $0.frame = bounds }
    }

    func host(_ layer: CALayer?) {
        guard let layer else { return }
        if layer.superlayer !== self.layer {
            layer.removeFromSuperlayer()
            self.layer.addSublayer(layer)
        }
        layer.frame = bounds
    }
}
#endif

// MARK: - Controls Overlay

/// System AirPlay route picker (AVKit). Native glyph, opens the receiver
/// list — picking an Apple TV hands video+audio over through AVPlayer's
/// built-in external playback.
#if os(iOS)
private struct AirPlayRoutePicker: UIViewRepresentable {
    /// true when the system route sheet is up — the caller must keep the
    /// controls alive (unmounting this view mid-presentation kills the
    /// picker: every later tap does nothing).
    var onPresentingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPresentingChanged: onPresentingChanged)
    }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = true
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        context.coordinator.onPresentingChanged = onPresentingChanged
    }

    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        var onPresentingChanged: (Bool) -> Void

        init(onPresentingChanged: @escaping (Bool) -> Void) {
            self.onPresentingChanged = onPresentingChanged
        }

        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            TJFLog("airplay: picker presenting BEGIN")
            // An INACTIVE audio session makes the receiver list come back empty
            // (engine only activates on play()). Activate here so the sheet
            // lists Apple TVs even when the user taps AirPlay while paused.
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                TJFLog("airplay: session activate FAILED \(error)")
            }
            onPresentingChanged(true)
        }

        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            TJFLog("airplay: picker presenting END")
            onPresentingChanged(false)
        }
    }
}
#endif

#if os(macOS)
private struct AirPlayRoutePicker: NSViewRepresentable {
    var onPresentingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPresentingChanged: onPresentingChanged)
    }

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        // macOS has no tintColor — per-state button colors instead.
        view.setRoutePickerButtonColor(.white, for: .normal)
        view.setRoutePickerButtonColor(.white, for: .normalHighlighted)
        view.setRoutePickerButtonColor(.systemBlue, for: .active)
        view.setRoutePickerButtonColor(.systemBlue, for: .activeHighlighted)
        view.isRoutePickerButtonBordered = false
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        context.coordinator.onPresentingChanged = onPresentingChanged
    }

    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        var onPresentingChanged: (Bool) -> Void

        init(onPresentingChanged: @escaping (Bool) -> Void) {
            self.onPresentingChanged = onPresentingChanged
        }

        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            TJFLog("airplay: picker presenting BEGIN")
            onPresentingChanged(true)
        }

        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            TJFLog("airplay: picker presenting END")
            onPresentingChanged(false)
        }
    }
}
#endif

/// Full-screen controls, laid out like the reference player:
/// top-left close + title/subtitle, top-right icon cluster (including the
/// persistent AirPlay picker), centered transport with previous/next
/// episode, and a full-width scrubber with segment ticks plus a
/// "Termina a las HH:mm" estimate.
private struct ControlsOverlay: View {
    let title: String
    var subtitle: String? = nil
    let viewModel: PlayerViewModel
    let onDismiss: () -> Void
    let onToggleFullscreen: () -> Void
    /// System route-sheet presentation state, bubbled up so the host can
    /// freeze the controls auto-hide while the sheet is on screen.
    var onAirPlayPresenting: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Spacer()

            transportRow

            Spacer()

            bottomBar
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            #if !os(macOS)
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
            }
            #endif

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Right cluster — every button drives a real action. AirPlay is a
            // system AVRoutePickerView (no public "present" API): it lives HERE,
            // mounted for the player's whole lifetime, so its glyph sits exactly
            // on the cluster baseline and the controls auto-hide never unmounts
            // it (remounting mid-presentation leaves the route sheet dead).
            HStack(spacing: 6) {
                #if os(macOS)
                clusterButton("arrow.up.left.and.arrow.down.right", action: onToggleFullscreen)
                #endif
                #if os(iOS)
                if viewModel.isPipWindowActive {
                    // Floating already — pull playback back into fullscreen.
                    clusterButton("pip.exit") {
                        Task { await viewModel.resumeFromPictureInPicture() }
                    }
                } else {
                    // Native PiP: no playlist resolve — startPictureInPicture is
                    // a thin call over the shared AVPlayerLayer, so the control
                    // never needs a warm-up state.
                    clusterButton("pip") {
                        Task { await viewModel.startPictureInPicture() }
                    }
                    .disabled(!viewModel.isPlaying && viewModel.currentTime <= 0)
                }
                #endif
                clusterButton("4k.tv", disabled: false) {
                    viewModel.showQualityPicker = true
                }
                // Favorite (P7): real server flag, optimistic toggle + rollback.
                clusterButton(
                    viewModel.isFavorite ? "heart.fill" : "heart",
                    disabled: viewModel.isTogglingFavorite
                ) {
                    Task { await viewModel.toggleFavorite() }
                }
                .accessibilityLabel(viewModel.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos")
                clusterButton("gauge", disabled: false) {
                    viewModel.showSpeedPicker = true
                }
                clusterButton(
                    "speaker.wave.2",
                    disabled: viewModel.availableAudioTracks.isEmpty
                ) {
                    viewModel.showAudioPicker = true
                }
                clusterButton(
                    "text.bubble",
                    disabled: viewModel.availableSubtitleTracks.isEmpty && viewModel.unavailableSubtitleTracks.isEmpty
                ) {
                    viewModel.showSubtitlePicker = true
                }
                #if os(iOS) || os(macOS)
                AirPlayRoutePicker(onPresentingChanged: onAirPlayPresenting)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.4), in: Circle())
                #endif
                #if os(iOS)
                // Cast: tecnología DIFERENTE de AirPlay (glifo propio, flujo
                // propio). Conectado → emite directo; sin sesión → selector.
                CastButton(
                    isConnected: viewModel.isCastConnected,
                    isConnecting: viewModel.castController?.isConnecting ?? false
                ) {
                    if viewModel.isCastConnected {
                        Task { await viewModel.castCurrentItem() }
                    } else {
                        viewModel.showCastPicker = true
                    }
                }
                #endif
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func clusterButton(
        _ icon: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.4), in: Circle())
                .opacity(disabled ? 0.35 : 1)
        }
        .disabled(disabled)
    }

    // MARK: Transport

    private var transportRow: some View {
        HStack(spacing: 36) {
            // ⏮ previous episode — only when DetailView/DirectPlayer wired one.
            transportButton(
                icon: "backward.end.alt.fill",
                size: 26,
                disabled: !viewModel.hasPreviousEpisode
            ) {
                viewModel.playPreviousEpisode()
            }

            transportButton(icon: "gobackward.15", size: 34, disabled: false) {
                let target = max(0, viewModel.currentTime - 15)
                Task { await viewModel.seek(to: target) }
            }

            Button(action: { Task { await viewModel.togglePlayPause() } }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .shadow(radius: 4)
            }

            transportButton(icon: "goforward.30", size: 34, disabled: false) {
                let target = min(viewModel.duration, viewModel.currentTime + 30)
                Task { await viewModel.seek(to: target) }
            }

            // ⏭ next episode — jumps right away (an explicit tap is deliberate).
            transportButton(
                icon: "forward.end.alt.fill",
                size: 26,
                disabled: !viewModel.hasNextEpisode
            ) {
                viewModel.playNextNow()
            }
        }
    }

    private func transportButton(
        icon: String,
        size: CGFloat,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(.white)
                // No dark circle behind transport controls: the shadow already
                // separates them from bright video, and the empty disc read as
                // a bulky chrome the reference player doesn't have. Padding
                // keeps the tap target at 56×56.
                .padding(14)
                .contentShape(Circle())
                .shadow(radius: 2)
                .opacity(disabled ? 0.3 : 1)
        }
        .disabled(disabled)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            SeekBar(
                currentTime: viewModel.currentTime,
                duration: viewModel.duration,
                ticks: viewModel.segmentTicks
            ) { newTime in
                Task { await viewModel.seek(to: newTime) }
            }

            HStack {
                Text(formatTime(viewModel.currentTime))
                Spacer()
                Text("-" + formatTime(remaining))
            }
            .font(.caption)
            .foregroundStyle(.white)

            if let endsAt {
                Text("Termina a las \(endsAt)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var remaining: Double {
        max(0, viewModel.duration - viewModel.currentTime)
    }

    /// Clock time when playback ends — derived from the live remaining
    /// time so it stays accurate while the player runs.
    private var endsAt: String? {
        guard viewModel.duration > 0, remaining > 0 else { return nil }
        let endsAtDate = Date().addingTimeInterval(remaining)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: endsAtDate)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Seek Bar

private struct SeekBar: View {
    let currentTime: Double
    let duration: Double
    /// 0...1 positions of segment markers drawn as ticks on the bar.
    var ticks: [Double] = []
    let onSeek: (Double) -> Void

    @State private var scrubTime: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.3))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(.white)
                    .frame(width: progressWidth(total: geo.size.width), height: 6)

                // Segment/chapter ticks (intro, recap, credits) drawn as
                // notches over the played track, like the reference bar.
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, fraction in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.black.opacity(0.55))
                        .frame(width: 2, height: 10)
                        .offset(x: geo.size.width * CGFloat(fraction) - 1)
                }

                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .offset(x: progressWidth(total: geo.size.width) - 7)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        scrubTime = fraction * duration
                    }
                    .onEnded { _ in
                        if let scrubTime {
                            onSeek(scrubTime)
                        }
                        scrubTime = nil
                    }
            )
            #endif
        }
        .frame(height: 20)
    }

    private func progressWidth(total: CGFloat) -> CGFloat {
        let time = scrubTime ?? currentTime
        guard duration > 0 else { return 0 }
        return total * CGFloat(time / duration)
    }
}

// MARK: - HUD Indicators

private struct SeekHUD: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.title3.bold())
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SeekIndicator: Equatable {
    let text: String
}

// MARK: - Skip Segment Overlay

/// Netflix-style skip button(s) shown when the playhead is inside an
/// intro / recap / credits segment.
private struct SkipSegmentOverlay: View {
    let segment: SegmentMarker
    let countdown: Double?
    let hasNextEpisode: Bool
    let onSkip: () -> Void
    let onPlayNext: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if segment.type == .credits {
                // Ending: two choices — skip to the end, or jump to next episode.
                if hasNextEpisode {
                    skipButton(label: "Siguiente episodio", icon: "forward.end.fill", action: onPlayNext)
                }
                skipButton(label: "Saltar créditos", icon: "arrow.right.to.line", action: onSkip)
            } else {
                skipButton(label: label, icon: "fastforward", action: onSkip)
            }

            if let countdown {
                Text("Auto en \(Int(countdown.rounded(.up)))s")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var label: String {
        switch segment.type {
        case .intro: "Saltar intro"
        case .recap: "Saltar resumen"
        case .credits: "Saltar créditos"
        }
    }

    /// Capsule pill matching the reference's bottom-right skip control:
    /// translucent gray fill, no hard border, white label.
    private func skipButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.gray.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheets

private struct AudioPickerSheet: View {
    let tracks: [AudioTrack]
    let selected: Int?
    let onSelect: (AudioTrack?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(tracks) { track in
                Button {
                    onSelect(track)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(track.name)
                            if let lang = track.languageName ?? track.language {
                                Text(lang).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if track.id == selected {
                            Image(systemName: "checkmark").foregroundStyle(MareaTheme.Colors.accent)
                        }
                    }
                }
            }
            .navigationTitle("Pista de audio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

private struct SubtitlePickerSheet: View {
    @Bindable var viewModel: PlayerViewModel
    let onSelect: (SubtitleTrack?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("Desactivados")
                        Spacer()
                        if viewModel.selectedSubtitleTrackIndex == nil
                            && viewModel.burnedInSubtitleServerIndex == nil {
                            Image(systemName: "checkmark").foregroundStyle(MareaTheme.Colors.accent)
                        }
                    }
                }

                ForEach(viewModel.availableSubtitleTracks) { track in
                    Button {
                        onSelect(track)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(track.name)
                                if let lang = track.languageName ?? track.language {
                                    Text(lang).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if track.id == viewModel.selectedSubtitleTrackIndex {
                                Image(systemName: "checkmark").foregroundStyle(MareaTheme.Colors.accent)
                            }
                        }
                    }
                }

                if !viewModel.unavailableSubtitleTracks.isEmpty {
                    Section {
                        Text("Estas pistas no están en el stream servido. Toca para cargarlas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Más subtítulos")
                    }
                    ForEach(viewModel.unavailableSubtitleTracks) { track in
                        Button {
                            Task {
                                switch track.reason {
                                case .downloadFailed:
                                    await viewModel.retrySubtitleDownload(serverIndex: track.id)
                                case .bitmapRequiresTranscode:
                                    await viewModel.switchSubtitleBurnIn(serverIndex: track.id)
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.name)
                                    if let lang = track.languageName {
                                        Text(lang).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(track.reason == .bitmapRequiresTranscode
                                        ? "\((track.codec ?? "IMG")) · requiere transcodificar"
                                        : "Descarga fallida · toca para reintentar")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if track.id == viewModel.burnedInSubtitleServerIndex {
                                    Image(systemName: "checkmark").foregroundStyle(MareaTheme.Colors.accent)
                                } else {
                                    Image(systemName: track.reason == .bitmapRequiresTranscode
                                        ? "film.stack"
                                        : "arrow.clockwise")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Button {
                    showSearch = true
                } label: {
                    Label("Buscar subtítulos…", systemImage: "magnifyingglass")
                }
            }
            .navigationTitle("Subtítulos")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            RemoteSubtitleSearchSheet(viewModel: viewModel)
        }
    }
}

private struct RemoteSubtitleSearchSheet: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Idioma (es, en…)", text: $viewModel.remoteSubtitleLanguage)
                            .noAutoCaps()
                            .disableAutocorrection(true)
                            .submitLabel(.search)
                            .onSubmit { Task { await viewModel.searchRemoteSubtitles() } }
                        if viewModel.isSearchingRemoteSubs {
                            ProgressView()
                        } else {
                            Button("Buscar") {
                                Task { await viewModel.searchRemoteSubtitles() }
                            }
                            .disabled(viewModel.remoteSubtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Text("Requiere un proveedor de subtítulos configurado en el servidor (p. ej. OpenSubtitles).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.remoteSubtitleError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    if viewModel.remoteSubtitleResults.isEmpty {
                        if viewModel.remoteSubsSearched && viewModel.remoteSubtitleError == nil {
                            Text("Sin resultados para ese idioma.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if !viewModel.remoteSubsSearched {
                            Text("Busca por idioma y toca un resultado para descargarlo sin detener la reproducción.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(viewModel.remoteSubtitleResults) { result in
                            Button {
                                Task {
                                    await viewModel.downloadAndSelectRemoteSubtitle(result)
                                    if viewModel.remoteSubtitleError == nil {
                                        // Track auto-selected: close search + picker.
                                        viewModel.showSubtitlePicker = false
                                        dismiss()
                                    }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.displayName)
                                        if let count = result.downloadCount {
                                            Text("\(count) descargas")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if viewModel.downloadingRemoteSubtitleId == result.id {
                                        ProgressView()
                                    } else if result.isHashMatch == true {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(MareaTheme.Colors.accent)
                                    }
                                }
                            }
                            .disabled(viewModel.downloadingRemoteSubtitleId != nil)
                        }
                    }
                }
            }
            .navigationTitle("Buscar subtítulos")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .onAppear {
            if viewModel.remoteSubtitleLanguage.isEmpty {
                viewModel.remoteSubtitleLanguage = viewModel.defaultRemoteSubtitleLanguage()
            }
        }
    }
}

private struct SpeedPickerSheet: View {
    let currentRate: Float
    let onSelect: (Float) -> Void
    @Environment(\.dismiss) private var dismiss

    private let speeds: [(label: String, rate: Float)] = [
        ("0.5x", 0.5),
        ("0.75x", 0.75),
        ("Normal", 1.0),
        ("1.25x", 1.25),
        ("1.5x", 1.5),
        ("2x", 2.0),
    ]

    var body: some View {
        NavigationStack {
            List(speeds, id: \.rate) { speed in
                Button {
                    onSelect(speed.rate)
                    dismiss()
                } label: {
                    HStack {
                        Text(speed.label)
                        Spacer()
                        if speed.rate == currentRate {
                            Image(systemName: "checkmark").foregroundStyle(MareaTheme.Colors.accent)
                        }
                    }
                }
            }
            .navigationTitle("Velocidad")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

private struct QualityPickerSheet: View {
    let current: StreamQuality
    let onSelect: (StreamQuality) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(StreamQuality.allCases) { quality in
                Button {
                    onSelect(quality)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quality.label)
                            Text(quality.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if quality == current {
                            Image(systemName: "checkmark").foregroundStyle(MareaTheme.Colors.accent)
                        }
                    }
                }
            }
            .navigationTitle("Calidad")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

/// Disable autocapitalization where the API exists (iOS/tvOS only —
/// macOS TextField has no such modifier and the shared player code builds
/// for all platforms).
private extension View {
    @ViewBuilder
    func noAutoCaps() -> some View {
        #if os(iOS) || os(tvOS) || os(visionOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

// MARK: - macOS Floating Close Button Window
#if os(macOS)
/// A SwiftUI-friendly wrapper that manages a floating NSPanel for the close button.
/// After toggleFullScreen, SwiftUI overlay buttons lose hit testing. This bypasses
/// the issue by placing the close button in its own window above the player.
private struct CloseButtonWindowRepresentable: NSViewRepresentable {
    let isVisible: Bool
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let hostView = NSView()
        DispatchQueue.main.async {
            context.coordinator.createWindow(hostView: hostView, onClose: onClose)
            if isVisible {
                context.coordinator.show()
            }
        }
        return hostView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isVisible {
            context.coordinator.show()
        } else {
            context.coordinator.hide()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        private var panel: NSPanel?
        private var onClose: (() -> Void)?
        private var playerWindowObserver: NSObjectProtocol?
        private var frameObservation: NSKeyValueObservation?
        private weak var playerWindow: NSWindow?
        private var closed = false

        func createWindow(hostView: NSView, onClose: @escaping () -> Void) {
            self.onClose = onClose

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 36, height: 36),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .utilityWindow

            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
            button.bezelStyle = .circular
            button.isBordered = false
            button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
            button.contentTintColor = .white
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(closeClicked)
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
            button.layer?.cornerRadius = 18

            panel.contentView = button
            self.panel = panel
        }

        func show() {
            guard let panel else { return }

            // Don't re-show after user clicked close
            if closed { return }

            // Find or re-find the player window (handles fullscreen window changes)
            if let pw = playerWindow, !pw.isVisible {
                // Player window changed (e.g. fullscreen transition) — find the new one
                self.playerWindow = findPlayerWindow()
            } else if playerWindow == nil {
                self.playerWindow = findPlayerWindow()
            }

            guard let playerWindow else { return }

            // Observe frame changes to reposition panel when window moves/resizes/fullscreens
            frameObservation?.invalidate()
            frameObservation = playerWindow.observe(\.frame) { [weak self] window, _ in
                Task { @MainActor in
                    self?.repositionPanel()
                }
            }

            // Also listen for fullscreen transitions which may change the window
            if playerWindowObserver == nil {
                playerWindowObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didEnterFullScreenNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    if let window = notification.object as? NSWindow,
                       window.title == playerWindow.title || window === playerWindow {
                        self?.playerWindow = window
                        self?.frameObservation?.invalidate()
                        self?.frameObservation = window.observe(\.frame) { [weak self] _, _ in
                            Task { @MainActor in
                                self?.repositionPanel()
                            }
                        }
                        // Reposition after a brief delay to let fullscreen animation settle
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            self?.repositionPanel()
                        }
                    }
                }
            }

            repositionPanel()
            panel.orderFront(nil)
        }

        func hide() {
            panel?.orderOut(nil)
        }

        func close() {
            frameObservation?.invalidate()
            frameObservation = nil
            if let obs = playerWindowObserver {
                NotificationCenter.default.removeObserver(obs)
                playerWindowObserver = nil
            }
            panel?.orderOut(nil)
            panel = nil
            playerWindow = nil
        }

        @objc private func closeClicked() {
            onClose?()
            panel?.orderOut(nil)
        }

        private func repositionPanel() {
            guard let panel, let playerWindow else { return }
            let origin = NSPoint(
                x: playerWindow.frame.origin.x + 16,
                y: playerWindow.frame.origin.y + playerWindow.frame.height - 52
            )
            panel.setFrameOrigin(origin)
        }

        /// Find the window that contains the VLC video player.
        /// During fullscreen, the window may be a different NSWindow instance.
        private func findPlayerWindow() -> NSWindow? {
            // Prefer the key window if it's playing video
            if let key = NSApp.keyWindow, key.contentView?.superview != nil {
                return key
            }
            // Fallback: find any visible window that could be the player
            return NSApp.windows.first {
                $0.isVisible && $0.level == .normal
            }
        }
    }
}
#endif

// MARK: - PiP Layer Host (iOS)

#if os(iOS)
/// Embeds the `AVPlayerLayer` of the active `PipCoordinator` session into the
/// ROOT view's hierarchy (always alive) so the system PiP window keeps a layer
/// inside the window even after the fullscreen player was dismissed. The system
/// window takes over rendering once it starts; while the app is foregrounded the
/// layer mirrors the floating window's content (same AVPlayer — nothing is
/// paused or re-prepared).
struct PipLayerHostView: UIViewRepresentable {
    let isActive: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        // Registered up front: the coordinator attaches the layer synchronously
        // when a session floats, so the host must already be known by then.
        PipCoordinator.shared.hostView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        PipCoordinator.shared.hostView = uiView
        guard isActive, let layer = PipCoordinator.shared.currentLayer else {
            uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            return
        }
        if layer.superlayer !== uiView.layer {
            uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            layer.frame = uiView.bounds
            uiView.layer.addSublayer(layer)
        } else {
            layer.frame = uiView.bounds
        }
    }
}
#endif

#if os(iOS)
/// Sheet del selector de Cast, extraído de la cadena principal del player:
/// la ViewBuilder del overlay ya es enorme y el type-checker se agotaba con
/// el modifier inline. La lógica vive aquí: al conectar desde el selector,
/// el contenido actual se lanza al receptor (conectar solo no emite); un
/// fallo de conexión cierra el sheet y se muestra como cápsula de estado.
struct CastPickerSheetModifier: ViewModifier {
    @Bindable var viewModel: PlayerViewModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $viewModel.showCastPicker) {
                CastDevicePickerSheet()
                    .onChange(of: viewModel.castController?.isConnected == true) { _, connected in
                        if connected {
                            viewModel.showCastPicker = false
                            Task { await viewModel.castCurrentItem() }
                        }
                    }
                    .onChange(of: viewModel.castController?.sessionState.phase) { _, phase in
                        if case .failed = phase {
                            viewModel.showCastPicker = false
                        }
                    }
            }
    }
}
#endif
