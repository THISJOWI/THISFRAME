import Foundation
import Observation
import ThisJellyFixCore
import ThisJellyFixNetworking
import ThisJellyFixPlayback
#if os(iOS)
import ThisJellyFixCast
#endif

@MainActor
@Observable
final class PlayerViewModel {
    // MARK: - Playback State
    var isPlaying = false
    /// True while playback is stopped **because the user asked for it**
    /// (play/pause control) — the auto-PiP gate must not float a pause away.
    var userPaused = false
    /// Whether an automatic PiP handoff (view exit / background) may run.
    var canAutoHandoffToPiP: Bool {
        // Emisión Cast: la salida activa es el receptor — flotar el video
        // local en PiP (parado) crearía una segunda salida incoherente.
        #if os(iOS)
        if isCastEmitting { return false }
        #endif
        // The rule lives in Core (`PiPHandoffPolicy`) so it is unit-tested.
        return PiPHandoffPolicy.canAutoStart(
            isPlaying: isPlaying,
            userPaused: userPaused,
            position: currentTime,
            duration: duration,
            engineStopped: engineStopped,
            hasError: errorMessage != nil
        )
    }
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Float = 1.0
    var isSeeking = false
    /// Target of a seek requested while another one is still in flight — the
    /// running pass hands over to it instead of stacking concurrent position sets.
    var pendingSeekTarget: Double?

    // MARK: - Tracks
    var availableAudioTracks: [AudioTrack] = []
    var availableSubtitleTracks: [SubtitleTrack] = []
    var selectedAudioTrackIndex: Int?
    var selectedSubtitleTrackIndex: Int?
    /// True once the user manually picked a subtitle track (or turned them
    /// off): preference auto-selection must not override that choice later.
    var subtitleSelectionLocked = false
    /// Manual subtitle language chosen by the user (e.g. "es"), preserved
    /// across episode swaps so the next episode re-picks the SAME language
    /// via fresh indices instead of falling back to the profile default.
    /// Nil = no manual language (follow profile prefs); `manualSubtitlesOff`
    /// covers the explicit-off case.
    private var manualSubtitleLanguage: String?
    /// True when the user explicitly turned subtitles off: episode swaps
    /// must stay off instead of auto-enabling via preferences.
    private var manualSubtitlesOff = false
    /// Bumped on every episode swap — async subtitle loads from a previous
    /// item must not populate the new item's lists.
    private var subtitleGeneration = 0
    /// Server stream index backing each overlay track (parallel to
    /// `externalSubs`): maps the metadata-ranked pick to the overlay id
    /// without reusing stale per-episode ids.
    private var externalSubServerIndices: [Int?] = []
    /// Subtitle tracks loaded as SRT from the server, with their cues.
    /// All subtitles are rendered exclusively by the SwiftUI client overlay (black background).
    private var externalSubs: [(track: SubtitleTrack, cues: [SubtitleCue])] = []
    /// Index into `externalSubs` when a subtitle track is selected.
    private var selectedExternalSubIndex: Int?
    /// Server-declared subtitle tracks without a playable overlay row:
    /// failed text downloads (tap retries) and bitmap tracks (tap burns in
    /// via transcode). Listed so nothing silently disappears.
    var unavailableSubtitleTracks: [UnavailableSubtitleTrack] = []
    /// Server indices of text tracks whose SRT download/parse failed.
    var failedSubtitleServerIndices: Set<Int> = []
    /// Server index of the bitmap subtitle currently burned into the served
    /// stream (pixels, not a legible track — no doubles possible). Nil =
    /// overlay stream (-1, the invariant).
    var burnedInSubtitleServerIndex: Int?
    /// Text for the SwiftUI subtitle overlay (black background).
    var subtitleText: String?

    // MARK: - UI State
    var showControls = true
    /// true = fill screen (crop), false = fit whole video (letterbox)
    var isFill = true
    var showAudioPicker = false
    var showSubtitlePicker = false
    var showSpeedPicker = false
    var showQualityPicker = false
    /// Selected quality cap; persisted so the next player opens with it.
    /// Reads/writes the single source of truth (`StreamQuality.persisted`).
    var selectedQuality: StreamQuality {
        didSet { UserDefaults.standard.set(selectedQuality.rawValue, forKey: Self.qualityDefaultsKey) }
    }
    var errorMessage: String?

    // MARK: - Skip Segments (intro / recap / credits)
    /// Current skip UI state — driven by the 0.5s playback timer.
    var activeSegment: SegmentMarker?
    /// Seconds until auto-skip fires inside `activeSegment` (nil = auto-skip off).
    var segmentCountdown: Double?
    /// Provided by the view: plays the next episode (nil when unavailable).
    var onPlayNextEpisode: (() -> Void)?
    /// true when a next-episode action is wired (credits shows both buttons).
    var hasNextEpisode = false
    /// Provided by the view: plays the PREVIOUS episode (nil when unavailable).
    var onPlayPreviousEpisode: (() -> Void)?
    /// true when a previous-episode action is wired (transport ⏮).
    var hasPreviousEpisode = false
    /// true while a next-episode swap is loading — the view covers the loading
    /// gap with an in-player indicator instead of dropping back out.
    var isSwitchingEpisode = false

    private var segmentDetector = SegmentDetector()
    private var segmentMarkers: [SegmentMarker] = []
    private var segmentClient: any JellyfinSegmentProviding
    private var segmentsLoaded = false
    private var segmentsLoadAttempts = 0
    private var skipInProgress = false

    // MARK: - Dependencies
    /// The one and only engine — the view hosts `engine.playerLayer` and the
    /// PiP coordinator hands the same layer to the system window.
    let engine: AVPlaybackEngine
    private var updateTimer: Timer?
    /// Fast cue refresh while an EXTERNAL track is composed client-side —
    /// riding the 0.5 s reporting tick made subtitles appear up to half a
    /// second late ("subtítulos desfasados").
    private var subtitleTimer: Timer?
    private var tracksLoaded = false
    private var trackLoadAttempts = 0
    private var timerTickCount = 0

    // MARK: - Server media streams (external subtitles)
    private var serverMediaStreams: [MediaStream] = []
    private var externalSubsLoaded = false
    /// Índice SERVIDOR (`MediaStream.index`) del audio que trae el stream
    /// actual: el pedido vía `AudioStreamIndex` o el default del servidor.
    /// Sin esto el picker solo vería el audio servido (remux/transcode traen
    /// uno solo) y el mapeo engine↔servidor sería una adivinanza por idioma.
    private var servedAudioServerIndex: Int?

    // MARK: - Favorite (P7 in-player toggle)
    /// Server is the source of truth (UserData): loaded on mount, optimistic
    /// toggle with rollback — never a local-only flag contradicting Jellyfin.
    var isFavorite = false
    var isFavoriteKnown = false
    var isTogglingFavorite = false
    var favoriteError: String?
    /// Injectable clients (tests).
    var userActionClient: any JellyfinUserActionProviding = JellyfinUserActionClient()
    var itemDetailClient: any JellyfinItemDetailProviding = JellyfinItemDetailClient()

    /// Load the server flag. Returns false when it could not be determined
    /// (toggle then refuses to flip blind instead of un-favoriting by mistake).
    @discardableResult
    func loadFavoriteState() async -> Bool {
        if isFavoriteKnown { return true }
        guard let userId, let serverURL, let token, let itemId else { return false }
        do {
            let detail = try await itemDetailClient.fetchItemDetail(
                userId: userId, serverURL: serverURL, token: token, itemId: itemId
            )
            isFavorite = detail.isFavorite
            isFavoriteKnown = true
            return true
        } catch {
            TJFLog("favorite: initial load failed — \(error.localizedDescription)")
            return false
        }
    }

    /// Optimistic toggle with rollback; concurrent taps collapse into one request.
    func toggleFavorite() async {
        // Zombie guard — a dismissed player must not fire user-data writes.
        guard !engineStopped, !isTogglingFavorite,
              let userId, let serverURL, let token, let itemId else { return }
        guard await loadFavoriteState() else {
            favoriteError = "No se pudo leer el estado de favorito."
            return
        }
        let desired = !isFavorite
        isFavorite = desired
        favoriteError = nil
        isTogglingFavorite = true
        defer { isTogglingFavorite = false }
        do {
            try await userActionClient.setFavorite(
                desired, userId: userId, serverURL: serverURL, token: token, itemId: itemId
            )
        } catch {
            isFavorite = !desired
            favoriteError = "No se pudo actualizar el favorito."
            TJFLog("favorite: toggle failed — \(error.localizedDescription)")
        }
    }

    func dismissFavoriteError() {
        favoriteError = nil
    }

    // MARK: - Remote subtitle search state (P6 sheet)
    /// Last search results (server providers); empty until searched.
    var remoteSubtitleResults: [RemoteSubtitleInfo] = []
    var isSearchingRemoteSubs = false
    var remoteSubtitleError: String?
    /// Prefilled from profile/system language; editable in the sheet.
    var remoteSubtitleLanguage: String = ""
    /// Result currently downloading (row spinner); nil when idle.
    var downloadingRemoteSubtitleId: String?
    /// True once a search ran (distinguishes "not searched yet" from "no results").
    var remoteSubsSearched = false
    /// Search sheet visibility (opened from the subtitle picker).
    var showSubtitleSearch = false
    /// Injectable search client (tests).
    var subtitleClient = JellyfinSubtitleClient()

    // MARK: - Playback Reporting
    private var reporter = JellyfinPlaybackReporter()
    private var reportingSessionId: String?
    private var hasReportedPlaying = false
    private var lastProgressReport: Date?
    private var itemId: String?
    private var serverURL: URL?
    private var token: String?
    private var userId: String?
    private var reportingConfigured = false

    // MARK: - Handoff takeover (playback moved to another device)
    /// Name of the device that took playback of the current item away from
    /// this one. Non-nil → the view shows the black takeover screen.
    var handoffTakeoverDeviceName: String?
    /// true when this playback session STARTED from a received handoff
    /// continuation. The receiver sees the sender's still-active /Sessions
    /// entry for a few seconds and must NEVER yield back — both would stop.
    var receivedViaHandoff = false
    /// Injectable /Sessions client (tests).
    var sessionClient: any JellyfinSessionProviding = JellyfinSessionClient()
    /// One poll at a time — a slow server must not stack fetches on the tick.
    private var takeoverCheckInFlight = false

    // MARK: - Lock screen (Now Playing)
    private var nowPlayingActive = false
    private var nowPlayingSession: Int?

    #if !os(visionOS)
    // MARK: - AirPlay route state
    /// Latest phase from the engine's route machine; nil until first event.
    private(set) var airplayPhase: AirPlayRouteState.Phase?
    /// True while a receiver handoff is negotiating (transport blocked).
    var isAirPlayConnecting: Bool {
        if case .connecting = airplayPhase { return true }
        return false
    }
    /// True while the receiver owns playback (green "transmitting" capsule).
    var isAirPlayActive: Bool {
        if case .active = airplayPhase { return true }
        return false
    }
    /// Dismiss a sticky failure capsule back to idle.
    func dismissAirPlayMessage() {
        engine.resetAirPlayRoute()
        airplayPhase = nil
        airplayMessage = nil
    }
    /// Transient status line: connection failure shown until the next event.
    var airplayMessage: String?
    #endif

    #if os(iOS)
    // MARK: - Google Cast (iOS only — no SDK on macOS/tvOS/visionOS)
    /// Salida remota Cast. Cargada por defecto; el test la sustituye.
    var castController: CastController?
    /// Sheet del selector de dispositivos.
    var showCastPicker = false
    /// El transporte (play/pause/seek) va al RECEPTOR, no al engine local.
    var isCastEmitting: Bool { castController?.isEmitting == true }
    /// Sesión Cast conectada (botón con punto rojo).
    var isCastConnected: Bool { castController?.isConnected ?? false }
    /// Mensaje de error Cast mostrado hasta el próximo evento.
    var castMessage: String?
    /// true durante el swap de episodio cuando el anterior terminÓ EN EL
    /// RECEPTOR con sesión viva: el nuevo episodio se emite, no se reproduce
    /// localmente (los episodios consecutivos siguen en el Chromecast).
    private var castCarryOver = false
    #endif

    init(
        engine: AVPlaybackEngine = AVPlaybackEngine(),
        segmentClient: any JellyfinSegmentProviding = JellyfinSegmentClient()
    ) {
        self.engine = engine
        self.segmentClient = segmentClient
        selectedQuality = StreamQuality.persisted
        // Real state machine: .failed surfaces a message, .ended is the true
        // end-of-media signal (the `duration - 1.5` guess is gone).
        engine.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.handleEngineState(state)
            }
        }
        #if !os(visionOS)
        engine.onRouteStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.handleRouteState(state)
            }
        }
        #endif
        // Lock-screen / headphone remote commands → the same VM entry points.
        let np = NowPlayingController.shared
        np.onPlay = { [weak self] in
            guard let self, !self.isPlaying else { return }
            Task { await self.togglePlayPause() }
        }
        np.onPause = { [weak self] in
            guard let self, self.isPlaying else { return }
            Task { await self.togglePlayPause() }
        }
        np.onTogglePlayPause = { [weak self] in
            Task { await self?.togglePlayPause() }
        }
        np.onSkipBackward = { [weak self] in
            Task { await self?.seekRelative(-15) }
        }
        np.onSkipForward = { [weak self] in
            Task { await self?.seekRelative(15) }
        }
        np.onSeek = { [weak self] position in
            Task { await self?.seek(to: position) }
        }

        #if os(iOS)
        // Cast: el controller es singleton (la sesión vive más que el player).
        // El hook reenvía el estado del RECEPTOR a la UI del player.
        castController = CastController.shared
        castController?.onMediaStatus = { [weak self] status in
            Task { @MainActor [weak self] in self?.handleCastMediaStatus(status) }
        }
        #endif
    }

    #if os(iOS)
    // MARK: - Cast

    /// Estado del receptor → UI del player (posición/duración/play-pause).
    /// El engine local está parado mientras se emite: el timer NO debe
    /// sobreescribir con las lecturas del AVPlayer detenido.
    private func handleCastMediaStatus(_ status: CastMediaState) {
        guard !engineStopped else { return }
        if !isSeeking { currentTime = status.position }
        if let duration = status.duration { self.duration = duration }
        if let playing = status.isPlaying { isPlaying = playing }
        NowPlayingController.shared.update(
            time: currentTime,
            duration: duration,
            rate: isPlaying ? playbackRate : Float(0)
        )
        if status.ended {
            // El contenido terminó en el receptor. Si hay cadena de
            // episodios, auto-avanzar EMITIENDO el siguiente en el receptor
            // (castCarryOver lo mantiene emitiendo durante el swap; sin
            // cadena, la salida vuelve a control local).
            TJFLog("cast: receptor terminó — hasNextEpisode=\(hasNextEpisode)")
            if hasNextEpisode {
                #if os(iOS)
                castCarryOver = castController?.isConnected ?? false
                #endif
                onPlayNextEpisode?()
            }
        }
        if let error = status.errorMessage { castMessage = error }
    }

    /// Emite el contenido ACTUAL del player al dispositivo conectado.
    /// Pausa el engine local (una sola salida sonora a la vez) y carga el
    /// stream en el receptor — reanudando desde la posición actual.
    func castCurrentItem() async {
        guard let castController, let url = currentStreamURL,
              let itemId, let serverURL, let token, let userId else {
            castMessage = "No hay contenido reproducible para emitir."
            return
        }
        guard castController.isConnected else {
            showCastPicker = true
            return
        }
        do {
            // Regla de convivencia: UNA salida activa. La reproducción local
            // se pausa; AirPlay es externo al engine y el usuario lo gestiona
            // con su propio picker (no se toca).
            engine.pause()
            isPlaying = false
            userPaused = true

            try await castController.cast(
                url: url,
                itemId: itemId,
                mediaSourceId: itemId,
                userId: userId,
                serverURL: serverURL,
                token: token,
                playSessionId: reportingSessionId,
                title: playbackTitle.isEmpty ? "ThisJellyFix" : playbackTitle,
                subtitle: nil,
                artworkURL: serverURL.appendingPathComponent("Items/\(itemId)/Images/Primary?maxWidth=400&quality=90"),
                startTime: currentTime > 5 ? currentTime : nil
            )
            castMessage = nil
        } catch {
            castMessage = error.localizedDescription
            TJFLog("cast: emisión fallida \(error.localizedDescription)")
        }
    }

    /// Desconexión elegida en el sheet: retoma la reproducción local desde
    /// la posición del receptor (vuelta local técnicamente posible).
    func castDisconnectedByUser() async {
        guard let castController, castController.isEmitting else { return }
        let position = castController.media.position
        castController.disconnect()
        castMessage = nil
        // El engine quedó pausado al emitir: reanudar LOCAL en la posición
        // del receptor. Si el engine murió (view reciclada), no tocar nada.
        guard !engineStopped else { return }
        if position > 0 {
            await engine.seek(to: position)
            currentTime = position
        }
        engine.play()
        isPlaying = true
        userPaused = false
        stopReported = false
    }
    #endif

    /// Lock screen / Control Center: publish what's playing (title + poster).
    /// Called once when the player mounts; the timer keeps time/rate fresh.
    func configureNowPlaying(title: String) {
        // Idempotent, BEFORE the guard: a restored session (PiP float tapped
        // again) already has nowPlayingActive = true but the view re-appearing
        // must re-claim Handoff (m5: float used to leave browsing suppressed
        // with no player advertising `playing`).
        HandoffCenter.shared.setPlaybackActive(true)
        guard !nowPlayingActive else { return }
        nowPlayingActive = true
        nowPlayingSession = NowPlayingController.shared.activate(title: title, duration: duration)
        if let serverURL, let itemId {
            let artwork = URL(string: "\(serverURL.absoluteString)/Items/\(itemId)/Images/Primary?maxWidth=400&quality=90")
            NowPlayingController.shared.setArtworkURL(artwork)
        }
    }

    private func handleEngineState(_ state: PlaybackEngineState) {
        switch state {
        case .failed(let message):
            TJFLog("engine FAILED item=\(itemId ?? "nil"): \(message)")
            isPlaying = false
            if errorMessage == nil {
                errorMessage = message
            }
        case .ended:
            // Natural end — credits/next-episode UI keep showing, no error.
            TJFLog("engine ENDED item=\(itemId ?? "nil")")
            isPlaying = false
        case .buffering, .loading, .ready, .playing, .paused, .idle:
            break
        }
    }

    #if !os(visionOS)
    /// AirPlay route machine → UI state. During a connect window the timer's
    /// `timeControlStatus` sampling makes the screen FLICKER to "paused";
    /// the phase (not the sample) is what the status line and transport guard
    /// follow.
    private func handleRouteState(_ state: AirPlayRouteState) {
        // m1: async events enqueued before teardown (Task/Dispatch main) can
        // arrive after stopSync cleared the phase — drop them instead of
        // resurrecting stale UI state.
        guard !engineStopped else { return }
        airplayPhase = state.phase
        switch state.phase {
        case .connecting(let name):
            airplayMessage = nil
            TJFLog("airplay: vm connecting route=\(name)")
        case .active:
            airplayMessage = nil
            // Ground truth from AVPlayer — resync whatever the timer guessed.
            isPlaying = engine.isPlaying
            TJFLog("airplay: vm external active isPlaying=\(isPlaying)")
        case .failed(let reason):
            airplayMessage = reason
            // Local playback never stopped; make the UI reflect that.
            isPlaying = engine.isPlaying
        case .idle:
            airplayMessage = nil
            isPlaying = engine.isPlaying
        }
    }
    #endif

    /// Configure playback reporting. Call before starting playback.
    func configureReporting(userId: String, serverURL: URL, token: String, itemId: String, playSessionId: String? = nil) {
        self.userId = userId
        self.serverURL = serverURL
        self.token = token
        self.itemId = itemId
        // Echo the server-issued PlaySessionId so reports attach to the right session.
        self.reportingSessionId = playSessionId ?? UUID().uuidString
        self.reporter.playSessionId = playSessionId
        self.reportingConfigured = true
        TJFLog("configureReporting OK itemId=\(itemId) server=\(serverURL.absoluteString) user=\(userId) tokenLen=\(token.count) playSessionId=\(playSessionId ?? "nil")")
    }

    /// Server-declared media streams — used to find external subtitle files
    /// that don't exist inside the container AVPlayer parses.
    func configureMediaStreams(_ streams: [MediaStream]) {
        serverMediaStreams = streams
        TJFLog("configureMediaStreams total=\(streams.count) extSubs=\(streams.filter { $0.type == "Subtitle" && $0.isExternal == true }.count)")
    }

    /// Audio SERVIDOR que trae el stream actual (`MediaStream.index` pedido
    /// o default). Registra, sin tocar playback: el stream YA es ese; solo
    /// corrige el mapeo engine↔servidor del picker (llega en render aparte).
    func noteServedAudioServerIndex(_ index: Int?) {
        guard servedAudioServerIndex != index else { return }
        servedAudioServerIndex = index
        // Re-mapear con el dato bueno (la unión anterior pudo adivinar).
        tracksLoaded = false
        trackLoadAttempts = 0
    }

    // MARK: - Playback Control

    /// Stream URL of the current playback — the PiP context carries it so the
    /// root view can rebuild the fullscreen player after a floating window.
    private var currentStreamURL: URL?
    /// True once the engine has been stopped (view disappeared).
    private(set) var engineStopped = false
    /// A stop report was already sent for this item — teardown must not
    /// send a second, stale one (float→close→exit chains).
    private var stopReported = false
    /// Resume target not yet reached. Progress/stop reports never send a
    /// lower position while it is pending, so exiting before the resume seek
    /// lands cannot overwrite the server's saved resume point with 0.
    private var pendingResumePosition: Double?
    /// Last time a seek landed — used to tell "user scrubbed here on purpose"
    /// from "playback drifted into an auto-skippable segment".
    private var lastSeekAt: Date?
    /// Display title — carried into the PiP context for restore.
    var playbackTitle: String = ""

    func prepareStream(url: URL, startPosition: Double? = nil) async {
        do {
            // Fresh attempt: a stale error must not block the exit handoff later.
            errorMessage = nil
            #if os(iOS)
            // A floating session must not keep playing (and reporting) over a
            // new fullscreen playback — one live session at a time.
            PipCoordinator.shared.closeFloating()
            PipCoordinator.shared.configure(engine: engine)
            #endif
            // Track the resume target from here so reports can never fall
            // below it until the post-play seek actually lands.
            pendingResumePosition = (startPosition ?? 0) > 0 ? startPosition : nil
            let request = PlaybackRequest(itemID: itemId ?? "", streamURL: url, startTime: startPosition)
            try await engine.prepare(request)
            // The view can vanish mid-prepare (task cancelled in onDisappear):
            // re-arming `engineStopped = false` here would let a zombie
            // continuation play audio on a player nobody can see.
            guard !Task.isCancelled else { return }
            currentStreamURL = url
            engineStopped = false
            stopReported = false
            // Apply the persisted fit/fill mode natively so subtitles stay
            // inside the visible region from the start.
            engine.setVideoFill(isFill)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayPause() async {
        // Zombie guard: playback work that outlived the player (dismissal
        // during the post-prepare delay) must not restart audio.
        guard !engineStopped else { return }
        #if os(iOS)
        // Emisión Cast: el transporte va al RECEPTOR (el engine local está
        // pausado y no debe reanudarse por accidente).
        if isCastEmitting {
            if isPlaying {
                castController?.pause()
                isPlaying = false
            } else {
                castController?.play()
                isPlaying = true
            }
            userPaused = !isPlaying
            return
        }
        #endif
        #if !os(visionOS)
        // A1: play/pause while a receiver handoff is negotiating aborts the
        // connection in AVPlayer — the "starts but never completes" race.
        if engine.routeState.blocksTransportCommands {
            TJFLog("airplay: transport command ignored — handoff connecting")
            return
        }
        #endif
        if isPlaying {
            engine.pause()
            userPaused = true
        } else {
            engine.play()
            userPaused = false
            // The user resumed in THIS mount: reporting is live again, so a
            // later exit may report its stop (a stale flag from a closed
            // floating window would block it).
            stopReported = false
        }
        isPlaying.toggle()
    }

    // MARK: - Episode Switching

    /// Swap to another episode WITHOUT tearing the player down.
    ///
    /// Forgets every per-item state, then feeds the new stream to the same
    /// AVPlayer (replaceCurrentItem keeps the layer and PiP wiring intact).
    func switchToEpisode(
        url: URL,
        startPosition: Double?,
        itemId: String?,
        serverURL: URL?,
        token: String?,
        userId: String?,
        playSessionId: String?,
        mediaStreams: [MediaStream],
        audioServerIndex: Int? = nil
    ) async {
        isSwitchingEpisode = true
        defer { isSwitchingEpisode = false }

        endCurrentItemSession()
        resetItemState()

        if let itemId, let serverURL, let token, let userId {
            configureReporting(
                userId: userId, serverURL: serverURL, token: token,
                itemId: itemId, playSessionId: playSessionId
            )
        } else {
            reportingConfigured = false
        }
        configureMediaStreams(mediaStreams)
        servedAudioServerIndex = audioServerIndex

        engine.stop()
        // Dismissed mid-swap: the task is cancelled in onDisappear, and a
        // zombie continuation would call play() + startUpdating() on a view
        // that is already gone.
        guard !Task.isCancelled, !engineStopped else { return }

        #if os(iOS)
        // Swap dentro de una cadena Cast: el episodio se EMITE en el
        // receptor (el stream local ni siquiera se prepara). Si la URL
        // resuelta no sirve para el receptor (p. ej. mkv directo), el
        // controller la re-resolve con el perfil chromecast.
        if castCarryOver, let castController, castController.isConnected {
            castCarryOver = false
            if let itemId, let serverURL, let token, let userId {
                do {
                    try await castController.cast(
                        url: url,
                        itemId: itemId,
                        mediaSourceId: itemId,
                        userId: userId,
                        serverURL: serverURL,
                        token: token,
                        playSessionId: playSessionId,
                        title: playbackTitle.isEmpty ? "ThisJellyFix" : playbackTitle,
                        subtitle: nil,
                        artworkURL: serverURL.appendingPathComponent(
                            "Items/\(itemId)/Images/Primary?maxWidth=400&quality=90"
                        ),
                        startTime: nil
                    )
                    isPlaying = true
                    userPaused = false
                    startUpdating()
                    TJFLog("cast: swap de episodio — siguiente emitido en el receptor")
                } catch {
                    castMessage = error.localizedDescription
                    TJFLog("cast: swap fallido, vuelta a local \\(error.localizedDescription)")
                }
            }
            return
        }
        castCarryOver = false
        #endif

        await prepareStream(url: url, startPosition: startPosition)
        guard !Task.isCancelled else { return }
        engine.play()
        guard !Task.isCancelled else { return }
        isPlaying = true
        userPaused = false
        startUpdating()
        // New item → its own server favorite flag (fire-and-forget: playback
        // is already running, the heart fills in when the fetch lands).
        Task { await loadFavoriteState() }
        if let startPosition, startPosition > 0 {
            await seek(to: startPosition)
        }
    }

    // MARK: - Quality

    private static var qualityDefaultsKey: String { StreamQuality.defaultsKey }

    /// Re-resolves the stream under a different bitrate ceiling and hot-swaps
    /// it in place, keeping position, play/pause state and playback rate.
    ///
    /// `.auto` drops the cap and asks the server for its original plan again
    /// (direct play / remux when the network allows it).
    func switchQuality(_ quality: StreamQuality) async {
        guard !engineStopped, !Task.isCancelled,
              let userId, let serverURL, let token, let itemId else { return }
        selectedQuality = quality
        let position = currentTime
        let wasPlaying = isPlaying
        let rate = playbackRate
        // Swapping the item tears down the external session: stop() resets
        // the route machine, so an active AirPlay session dies silently here.
        // Warn instead of pretending the receiver follows along.
        let wasExternallyActive = engine.player.isExternalPlaybackActive

        // El cambio de calidad preserva audio servido y burn-in activo
        // (subs -1 en caso contrario: invariante anti-dobles).
        guard let swapped = await fetchPlaybackSwap(
            audioServerIndex: servedAudioServerIndex,
            subtitleServerIndex: burnedInSubtitleServerIndex,
            burnInSubtitle: burnedInSubtitleServerIndex != nil
        ) else { return }
        let delivery = swapped.url.absoluteString.contains(".m3u8") ? "transcode" : "direct"
        TJFLog("switchQuality: \(quality.label) cap=\(quality.maxBitrate.map(String.init) ?? "nil") delivery=\(delivery)")

        await hotSwapTo(
            url: swapped.url,
            playSessionId: swapped.playSessionId,
            mediaStreams: swapped.mediaStreams,
            audioServerIndex: servedAudioServerIndex,
            position: position,
            wasPlaying: wasPlaying,
            rate: rate
        )
        if wasExternallyActive {
            airplayMessage = "AirPlay detenido por el cambio de calidad — vuelve a seleccionarlo"
            TJFLog("airplay: quality swap ended external session — user must re-select")
        }
    }

    /// Hot-swap en caliente preservando posición, play/pausa y rate.
    /// `switchToEpisode` siempre deja playing: se restaura lo que había.
    private func hotSwapTo(
        url: URL,
        playSessionId: String?,
        mediaStreams: [MediaStream],
        audioServerIndex: Int?,
        position: Double,
        wasPlaying: Bool,
        rate: Float
    ) async {
        guard let userId, let serverURL, let token, let itemId else { return }
        await switchToEpisode(
            url: url,
            startPosition: position,
            itemId: itemId,
            serverURL: serverURL,
            token: token,
            userId: userId,
            playSessionId: playSessionId,
            mediaStreams: mediaStreams,
            audioServerIndex: audioServerIndex
        )
        if rate != 1.0 { await setPlaybackRate(rate) }
        if !wasPlaying {
            engine.pause()
            isPlaying = false
            userPaused = true
        }
    }

    /// Close out the previous item's Jellyfin session so the next episode
    /// starts a fresh one.
    private func endCurrentItemSession() {
        guard reportingConfigured else { return }
        #if os(iOS)
        if PipCoordinator.shared.isFloating {
            // The floating window owns the session — closing it reports the
            // stop itself. Programmatic close: no closed handlers fire.
            PipCoordinator.shared.closeFloating()
            return
        }
        #endif
        if !stopReported {
            reportStopped()
        }
    }

    /// Forget everything that belongs to the previous item.
    private func resetItemState() {
        // Invalidate any in-flight subtitle fetch for the old item before
        // dropping its lists — a slow response must not populate the new one.
        subtitleGeneration += 1
        availableAudioTracks = []
        availableSubtitleTracks = []
        selectedAudioTrackIndex = nil
        selectedSubtitleTrackIndex = nil
        // Per-item lock is cleared, but the MANUAL language/off choice
        // survives: the next episode re-picks the same language via fresh
        // indices (or stays off) instead of reverting to profile defaults.
        subtitleSelectionLocked = manualSubtitlesOff || manualSubtitleLanguage != nil
        externalSubs = []
        externalSubServerIndices = []
        selectedExternalSubIndex = nil
        subtitleText = nil
        unavailableSubtitleTracks = []
        failedSubtitleServerIndices = []
        burnedInSubtitleServerIndex = nil
        showAudioPicker = false
        showSubtitlePicker = false
        showSpeedPicker = false
        // A prior takeover ("continued on X, this device stopped") belongs to
        // the old item — a fresh item must never open on the black screen.
        handoffTakeoverDeviceName = nil
        // Remote subtitle search belongs to the old item too.
        remoteSubtitleResults = []
        remoteSubtitleError = nil
        remoteSubsSearched = false
        downloadingRemoteSubtitleId = nil
        // Favorite flag belongs to the old item: reload for the new one.
        isFavorite = false
        isFavoriteKnown = false
        favoriteError = nil

        errorMessage = nil
        isSeeking = false
        currentTime = 0
        duration = 0
        playbackRate = 1.0
        // nil → the timer re-reads the new item's size.
        videoAspect = nil

        segmentDetector.reset()
        segmentMarkers = []
        segmentsLoaded = false
        segmentsLoadAttempts = 0
        skipInProgress = false
        activeSegment = nil
        segmentCountdown = nil

        tracksLoaded = false
        trackLoadAttempts = 0
        timerTickCount = 0
        externalSubsLoaded = false

        hasReportedPlaying = false
        lastProgressReport = nil
        engineStopped = false
        stopReported = false
        pendingResumePosition = nil
        lastSeekAt = nil
    }

    func seek(to seconds: Double) async {
        // Zombie guard — a dismissed player must not keep positioning.
        guard !engineStopped else { return }
        #if os(iOS)
        // Emisión Cast: el seek va al receptor; la posición local solo se
        // sincroniza (el receiver la confirma por listener).
        if isCastEmitting {
            isSeeking = true
            currentTime = seconds
            castController?.seek(to: seconds)
            isSeeking = false
            return
        }
        #endif
        // Coalesce overlapping triggers (scrub release + auto-skip, double tap
        // ±15s, swipe while scrubbing).
        if isSeeking {
            pendingSeekTarget = seconds
            return
        }
        isSeeking = true
        var target = seconds
        while true {
            pendingSeekTarget = nil
            await performSeek(to: target)
            guard let next = pendingSeekTarget else { break }
            target = next
        }
        isSeeking = false
    }

    /// One seek pass: AVPlayer seeks are precise (zero tolerance) and the
    /// engine awaits the completion handler, so this only verifies the landing
    /// and clears the resume pin.
    private func performSeek(to seconds: Double) async {
        currentTime = seconds
        await engine.seek(to: seconds)
        guard !engineStopped else { return }

        let actual = engine.currentTime
        if abs(actual - seconds) <= 2.0 {
            // Landed — from here the real playback time is authoritative.
            pendingResumePosition = nil
        } else {
            TJFLog("seek: landed at \(String(format: "%.1f", actual))s (target \(String(format: "%.1f", seconds))s)")
        }
        lastSeekAt = Date()
        currentTime = actual
        // The timer skips subtitle updates while isSeeking — without this the
        // overlay kept the PRE-seek cue until the next 0.5s tick (subs lagging
        // after skipping the opening).
        updateSubtitleText()
    }

    func seekRelative(_ delta: Double) async {
        let target = max(0, min(currentTime + delta, duration))
        await seek(to: target)
    }

    func setPlaybackRate(_ rate: Float) async {
        engine.setPlaybackRate(rate)
        playbackRate = rate
    }

    /// Switch between fill (cover screen) and fit (whole video) modes.
    /// Applied to the AVPlayerLayer's videoGravity so subtitles follow the
    /// visible region.
    func setFill(_ fill: Bool) {
        guard fill != isFill else { return }
        isFill = fill
        engine.setVideoFill(fill)
    }

    /// Native video aspect ratio (width/height), nil until known.
    private(set) var videoAspect: CGFloat?

    // MARK: - Track Selection

    func selectAudioTrack(_ track: AudioTrack?) async {
        guard let track else { return }
        // Zombie guard (igual que subtítulos): sin engine vivo no se toca nada.
        guard !engineStopped else { return }
        if let engineIdx = track.engineIndex {
            // El stream servido trae este audio: cambio instantáneo.
            await engine.selectAudioTrack(index: engineIdx)
            selectedAudioTrackIndex = track.id
            return
        }
        guard let serverIdx = track.serverIndex else { return }
        // El servido no lo trae (remux/transcode mono-audio): pedirlo al
        // servidor y re-montar en caliente preservando posición/estado.
        await switchAudio(toServerIndex: serverIdx)
    }

    /// Cambia a un audio solo-declarado-por-el-servidor: re-pide PlaybackInfo
    /// con `AudioStreamIndex` y re-monta en caliente (mismo patrón que
    /// `switchQuality`: posición, play/pausa y rate se preservan).
    func switchAudio(toServerIndex serverIndex: Int) async {
        guard !engineStopped, !Task.isCancelled,
              let userId, let serverURL, let token, let itemId else { return }
        guard serverIndex != servedAudioServerIndex else {
            // Ya servido (carrera picker↔re-mapeo): solo marcar la fila.
            if let row = availableAudioTracks.first(where: { $0.serverIndex == serverIndex }) {
                selectedAudioTrackIndex = row.id
            }
            return
        }
        let position = currentTime
        let wasPlaying = isPlaying
        let rate = playbackRate
        TJFLog("switchAudio: serverIndex=\(serverIndex) pos=\(String(format: "%.1f", position))")
        guard let swapped = await fetchPlaybackSwap(
            audioServerIndex: serverIndex,
            subtitleServerIndex: burnedInSubtitleServerIndex,
            burnInSubtitle: burnedInSubtitleServerIndex != nil
        ) else { return }
        await hotSwapTo(
            url: swapped.url,
            playSessionId: swapped.playSessionId,
            mediaStreams: swapped.mediaStreams,
            audioServerIndex: serverIndex,
            position: position,
            wasPlaying: wasPlaying,
            rate: rate
        )
        if let row = availableAudioTracks.first(where: { $0.serverIndex == serverIndex }) {
            selectedAudioTrackIndex = row.id
        }
    }

    /// Activa una pista bitmap (PGS/VobSub/DVB) quemándola en el vídeo vía
    /// transcode: el overlay no renderiza píxeles. Hot-swap preservando
    /// posición/estado (mismo patrón que `switchAudio`). Quemado = píxeles,
    /// no pista legible: imposible el doble renderer.
    func switchSubtitleBurnIn(serverIndex idx: Int) async {
        guard !engineStopped, !Task.isCancelled else { return }
        guard burnedInSubtitleServerIndex != idx else { return }
        guard serverMediaStreams.contains(where: { $0.type == "Subtitle" && $0.index == idx }) else { return }
        let position = currentTime
        let wasPlaying = isPlaying
        let rate = playbackRate
        TJFLog("switchSubBurnIn: serverIndex=\(idx) pos=\(String(format: "%.1f", position))")
        guard let swapped = await fetchPlaybackSwap(
            audioServerIndex: servedAudioServerIndex,
            subtitleServerIndex: idx,
            burnInSubtitle: true
        ) else { return }
        await hotSwapTo(
            url: swapped.url,
            playSessionId: swapped.playSessionId,
            mediaStreams: swapped.mediaStreams,
            audioServerIndex: servedAudioServerIndex,
            position: position,
            wasPlaying: wasPlaying,
            rate: rate
        )
        burnedInSubtitleServerIndex = idx
        // Sin overlay encima de píxeles quemados (single renderer) y sin
        // auto-pick que lo pise.
        subtitleSelectionLocked = true
        selectedExternalSubIndex = nil
        selectedSubtitleTrackIndex = nil
        subtitleText = nil
        refreshSubtitleTimer()
    }

    /// Vuelve al stream overlay (-1, sin quemar) si hay un burn-in activo.
    /// False = el swap falló, el llamante debe abortar su selección.
    private func ensureOverlayStream() async -> Bool {
        guard burnedInSubtitleServerIndex != nil else { return true }
        guard !engineStopped, !Task.isCancelled else { return false }
        let position = currentTime
        let wasPlaying = isPlaying
        let rate = playbackRate
        TJFLog("subtitles: leaving burn-in, back to overlay stream")
        guard let swapped = await fetchPlaybackSwap(
            audioServerIndex: servedAudioServerIndex
        ) else { return false }
        await hotSwapTo(
            url: swapped.url,
            playSessionId: swapped.playSessionId,
            mediaStreams: swapped.mediaStreams,
            audioServerIndex: servedAudioServerIndex,
            position: position,
            wasPlaying: wasPlaying,
            rate: rate
        )
        burnedInSubtitleServerIndex = nil
        return true
    }

    /// Re-pide PlaybackInfo preservando el audio actual y resuelve la URL
    /// reproducible. Comparte la maquinaria de `switchQuality`,
    /// `switchAudio` y `switchSubtitleBurnIn` para no duplicar el ladder.
    /// Los subs van con -1 salvo burn-in explícito (invariante anti-dobles:
    /// nada mux/quemado salvo que el usuario lo pida; el overlay los
    /// re-descarga solo).
    private func fetchPlaybackSwap(
        audioServerIndex: Int?,
        subtitleServerIndex: Int? = nil,
        burnInSubtitle: Bool = false
    ) async -> (url: URL, playSessionId: String?, mediaStreams: [MediaStream])? {
        guard let userId, let serverURL, let token, let itemId else { return nil }
        do {
            let quality = selectedQuality
            let info = try await JellyfinPlaybackClient().fetchPlaybackInfo(
                userId: userId,
                serverURL: serverURL,
                token: token,
                itemId: itemId,
                deviceProfile: .avPlayer.capped(to: quality.maxBitrate),
                maxStreamingBitrate: quality.maxBitrate,
                subtitleStreamIndex: subtitleServerIndex ?? -1,
                alwaysBurnInSubtitleWhenTranscoding: burnInSubtitle ? true : false,
                audioStreamIndex: audioServerIndex
            )
            guard let source = info.mediaSources.first else {
                TJFLog("fetchPlaybackSwap: no media source")
                return nil
            }
            guard let url = StreamURLResolver.playbackURL(
                source: source,
                serverURL: serverURL,
                itemId: itemId,
                token: token
            ) else {
                TJFLog("fetchPlaybackSwap: unresolved stream URL")
                return nil
            }
            let delivery = source.transcodingUrl != nil ? "transcode" : "direct"
            TJFLog("fetchPlaybackSwap: delivery=\(delivery) audio=\(audioServerIndex.map(String.init) ?? "-")")
            return (url, info.playSessionId, source.mediaStreams)
        } catch {
            TJFLog("fetchPlaybackSwap failed: \(error)")
            return nil
        }
    }

    func selectSubtitleTrack(_ track: SubtitleTrack?) async {
        // Zombie guard: a dismissed player must not re-assert selections on a
        // dead engine (async picker tasks outliving the view could otherwise
        // flip state behind a floating PiP session).
        guard !engineStopped else { return }
        // Saliendo de un burn-in: primero volver al stream overlay (-1);
        // si ese swap falla, abortar para no mezclar estados.
        guard await ensureOverlayStream() else { return }
        // Manual choice — including explicit "Desactivados" — wins over the
        // stored preference for the rest of this item. Never recreates the
        // player item: PiP wiring (same AVPlayer/AVPlayerLayer) is untouched.
        subtitleSelectionLocked = true
        if let track {
            manualSubtitlesOff = false
            manualSubtitleLanguage = track.language
        } else {
            manualSubtitlesOff = true
        }
        await applySubtitleSelection(track)
    }

    /// Select a subtitle track rendered exclusively in the black-background overlay. nil = off.
    private func applySubtitleSelection(_ track: SubtitleTrack?) async {
        guard let track else {
            await engine.selectSubtitleTrack(index: -1)
            selectedExternalSubIndex = nil
            selectedSubtitleTrackIndex = nil
            subtitleText = nil
            refreshSubtitleTimer()
            return
        }
        // Subtitles are rendered exclusively by the client overlay with black background.
        // AVPlayer native legible rendering stays disabled in fullscreen (-1);
        // when PiP is already active the same language is mirrored natively
        // so the system window shows it (single renderer per surface).
        await engine.selectSubtitleTrack(index: -1)
        selectedExternalSubIndex = track.id
        selectedSubtitleTrackIndex = track.id
        updateSubtitleText()
        refreshSubtitleTimer()
        #if os(iOS)
        if PipCoordinator.shared.isWindowActive {
            applyPiPSubtitleMode(active: true)
        }
        #endif
        TJFLog("subtitles select id=\(track.id) name=\(track.name)")
    }

    /// Cue lookup for the overlay — runs on the fast subtitle timer.
    private func updateSubtitleText() {
        guard let idx = selectedExternalSubIndex, idx < externalSubs.count else {
            if subtitleText != nil { subtitleText = nil }
            return
        }
        // engine.currentTime is live; the sampled `currentTime` lags up to
        // 0.5 s behind and pushed every cue switch past the audio.
        let next = SRTParser.cue(at: engine.currentTime, in: externalSubs[idx].cues)?.text
        if next != subtitleText { subtitleText = next }
    }

    /// Start/stop the 0.2 s cue refresh to match the current selection.
    /// Cheap when off: the cue lookup is a binary search and the assignment
    /// only fires observation when the TEXT changes.
    private func refreshSubtitleTimer() {
        let wanted = selectedExternalSubIndex != nil && updateTimer != nil
        if wanted {
            guard subtitleTimer == nil else { return }
            subtitleTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    // Seek targets are held by performSeek — refresh there.
                    guard let self, !self.isSeeking else { return }
                    self.updateSubtitleText()
                    // External overlay path: the native layer must stay
                    // cleared, or both renderers show text at once. Runs
                    // here (not only on the 0.5 s tick) so an external-sub
                    // drift is corrected within one cue interval.
                    self.engine.reconcileSubtitleSelection()
                }
            }
        } else {
            subtitleTimer?.invalidate()
            subtitleTimer = nil
        }
    }

    // MARK: - Timer

    func startUpdating() {
        // Handoff races must never stack timers — a leaked timer keeps
        // reporting stale progress forever.
        guard updateTimer == nil else { return }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in            Task { @MainActor [weak self] in
                guard let self else { return }
                #if os(iOS)
                // Emisión Cast: el engine local está parado — sus lecturas
                // congelarían la UI en la posición del corte. El estado
                // llega del receptor vía handleCastMediaStatus; el tick solo
                // mantiene el reporte y el lock-screen.
                if self.isCastEmitting {
                    self.duration = self.castController?.media.duration ?? self.duration
                    NowPlayingController.shared.update(
                        time: self.currentTime,
                        duration: self.duration,
                        rate: self.isPlaying ? self.playbackRate : Float(0)
                    )
                    return
                }
                #endif
                if self.isSeeking {
                    // A seek holds `currentTime` at its target, but duration and
                    // play state don't depend on it — freezing the whole snapshot
                    // made the UI look hung for the entire seek window.
                    self.duration = self.engine.duration
                    self.isPlaying = self.engine.isPlaying
                } else {
                    self.currentTime = self.engine.currentTime
                    self.duration = self.engine.duration
                    self.isPlaying = self.engine.isPlaying
                    self.updateSubtitleText()
                    // Continuous legible-enforcement: AVPlayer can
                    // re-preselect a native subtitle after our select (the
                    // duplicated-subs race). Cheap drift check; re-asserts
                    // only when the native selection stopped matching.
                    self.engine.reconcileSubtitleSelection()
                }

                // Lock screen: elapsed/duration/rate refresh.
                NowPlayingController.shared.update(
                    time: self.currentTime,
                    duration: self.duration,
                    rate: self.isPlaying ? self.playbackRate : Float(0)
                )

                // Native video aspect (diagnostics + fit/fill logging)
                let vs = self.engine.videoSize
                if vs.width > 0, vs.height > 0 {
                    let aspect = vs.width / vs.height
                    if abs(aspect - (self.videoAspect ?? 0)) > 0.001 {
                        self.videoAspect = aspect
                        TJFLog("videoAspect=\(aspect) videoSize=\(vs.width)x\(vs.height)")
                    }
                } else if self.videoAspect == nil && self.timerTickCount <= 6 {
                    TJFLog("videoAspect PENDING videoSize=\(vs.width)x\(vs.height)")
                }

                // Diagnostic log (first 10 ticks only)
                self.timerTickCount += 1
                if self.timerTickCount <= 10 {
                    TJFLog("timer tick=\(self.timerTickCount) isPlaying=\(self.isPlaying) reportingConfigured=\(self.reportingConfigured) hasReported=\(self.hasReportedPlaying) time=\(self.currentTime) dur=\(self.duration)")
                }

                #if os(iOS)
                // Keep the system auto-start gate in sync with the policy:
                // a user-paused player must not float away on background.
                PipCoordinator.shared.setAutoStartEnabled(self.canAutoHandoffToPiP)
                #endif

                // Determine if playback is active — time advancement as fallback.
                let playbackActive = self.isPlaying || (self.currentTime > 0 && self.currentTime < self.duration)

                // Report "playing" once when playback starts.
                if self.reportingConfigured, playbackActive, !self.hasReportedPlaying {
                    self.hasReportedPlaying = true
                    self.reportPlayStarted()
                }

                // Report progress every 10 seconds.
                if self.reportingConfigured {
                    if playbackActive, let last = self.lastProgressReport,
                       Date().timeIntervalSince(last) >= 10 {
                        self.reportProgress()
                    } else if self.lastProgressReport == nil, self.currentTime > 0 {
                        self.reportProgress()
                    }
                }

                // The engine loads media selection groups OFF the prepare
                // critical path (network metadata), so this poll is how the
                // VM picks them up. Wide window: a cold/remote server can
                // take several seconds for the two group loads.
                if !self.tracksLoaded {
                    self.trackLoadAttempts += 1
                    if self.trackLoadAttempts <= 60 {
                        await self.loadTracks()
                    } else {
                        TJFLog("tracks: VM gave up after \(self.trackLoadAttempts) attempts")
                        self.tracksLoaded = true
                    }
                }

                // Skip segments: fetch markers once, then evaluate every tick
                await self.loadSegmentsIfNeeded()
                self.evaluateSkipState(delta: 0.5)

                // Handoff takeover poll — every 10th tick (≈5 s) while this
                // session still owns playback.
                if self.timerTickCount % 10 == 0, !self.stopReported, !self.engineStopped {
                    await self.checkHandoffTakeover()
                }
            }
        }
        // External cue refresh runs alongside the reporting tick.
        refreshSubtitleTimer()
    }

    func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
        subtitleTimer?.invalidate()
        subtitleTimer = nil
    }

    // MARK: - Skip Segments

    /// Fetches skip markers once per playback session. Network/plugin failures
    /// degrade silently after a couple of attempts — the player works normally.
    private func loadSegmentsIfNeeded() async {
        guard !segmentsLoaded else { return }
        guard reportingConfigured, let serverURL, let token, let userId, let itemId else { return }
        segmentsLoadAttempts += 1
        do {
            let markers = try await segmentClient.fetchSegments(
                serverURL: serverURL,
                token: token,
                userId: userId,
                itemId: itemId
            )
            segmentMarkers = markers
            segmentsLoaded = true
        } catch {
            TJFLog("segments fetch error attempt=\(segmentsLoadAttempts): \(error)")
            if segmentsLoadAttempts >= 3 {
                segmentsLoaded = true // give up quietly
            }
        }
    }

    private func evaluateSkipState(delta: Double) {
        guard !skipInProgress else { return }
        // Freeze countdown while paused or seeking — only advance during playback.
        let effectiveDelta = (isPlaying && !isSeeking) ? delta : 0
        let settings = SkipSettings.current()
        let outcome = segmentDetector.tick(
            time: currentTime,
            delta: effectiveDelta,
            markers: segmentMarkers,
            settings: settings
        )
        switch outcome {
        case .none:
            activeSegment = nil
            segmentCountdown = nil
        case .show(let marker, let countdown):
            activeSegment = marker
            segmentCountdown = countdown
        case .triggerSkip(let marker):
            activeSegment = marker
            segmentCountdown = nil
            segmentDetector.markSkipped(marker)
            // Scrubbing INTO a segment is deliberate: offer the skip button
            // instead of hijacking playback a few seconds later.
            if lastSeekAt.map({ Date().timeIntervalSince($0) > 8 }) ?? true {
                Task { await performSkip(marker) }
            }
        }
    }

    /// Skip action for the overlay button: jump to the end of the segment.
    func skipActiveSegment() {
        guard let marker = activeSegment, !skipInProgress else { return }
        segmentDetector.markSkipped(marker)
        Task { await performSkip(marker) }
    }

    /// Ending segment: offer/trigger next episode playback.
    func playNextEpisode() {
        guard activeSegment?.type == .credits else { return }
        onPlayNextEpisode?()
    }

    /// Transport ⏮ — jump to the previous episode when one is wired.
    func playPreviousEpisode() {
        guard hasPreviousEpisode else { return }
        onPlayPreviousEpisode?()
    }

    /// Transport ⏭ — jump to the next episode right away. Unlike
    /// `playNextEpisode` (credits auto-offer) an explicit tap is deliberate,
    /// so no credits-segment guard.
    func playNextNow() {
        guard hasNextEpisode else { return }
        onPlayNextEpisode?()
    }

    /// Segment start positions as 0...1 fractions of the duration — the seek
    /// bar draws chapter ticks at these spots (nil-safe, skips zero duration).
    var segmentTicks: [Double] {
        Self.tickFractions(markers: segmentMarkers, duration: duration)
    }

    /// Pure tick math: marker starts normalized to the duration, dropping
    /// markers at t=0 (the bar's left edge already marks the start) and any
    /// that would fall past the end.
    static func tickFractions(markers: [SegmentMarker], duration: Double) -> [Double] {
        guard duration > 0 else { return [] }
        return markers
            .filter { $0.start > 0 && $0.start < duration }
            .map { $0.start / duration }
    }

    private func performSkip(_ marker: SegmentMarker) async {
        skipInProgress = true
        defer {
            skipInProgress = false
            activeSegment = nil
            segmentCountdown = nil
        }
        let target: Double
        if let end = marker.end {
            target = end
        } else {
            // Chapter-derived marker running to video end: skip to the very end.
            target = max(0, duration - 0.5)
        }
        guard target > currentTime else { return }
        TJFLog("skip \(marker.type.rawValue) → \(Int(target))s")
        await seek(to: target)
    }

    // MARK: - Private

    private func loadTracks() async {
        let union = unionAudioTracks(engineTracks: await engine.availableAudioTracks)
        // Reconstruye mientras haya novedad (el engine aterriza tarde, el
        // servido llega en render aparte): congela solo cuando estabiliza.
        if union != availableAudioTracks {
            availableAudioTracks = union
            // La selección visual sigue al audio servido aunque la lista
            // llegara después (o se re-mapeara con el índice tardío).
            if selectedAudioTrackIndex == nil,
               let served = servedAudioServerIndex,
               let row = union.first(where: { $0.serverIndex == served }) {
                selectedAudioTrackIndex = row.id
            }
        }

        TJFLog("loadTracks audio=\(availableAudioTracks.count) subs=\(availableSubtitleTracks.count) ext=\(externalSubs.count) attempt=\(trackLoadAttempts)")

        if !availableAudioTracks.isEmpty || !externalSubs.isEmpty {
            tracksLoaded = true
        }

        await addExternalSubtitlesIfNeeded()
        // Fullscreen invariant: native legible stays off (overlay renders).
        // While PiP is active the native track IS the renderer — forcing -1
        // here would mute PiP subs on every poll until tracks settle.
        #if os(iOS)
        if PipCoordinator.shared.isWindowActive {
            applyPiPSubtitleMode(active: true)
        } else {
            await engine.selectSubtitleTrack(index: -1)
        }
        #else
        await engine.selectSubtitleTrack(index: -1)
        #endif
    }

    // MARK: - Track display names

    /// Unión engine + servidor para el picker de audio.
    ///
    /// Un remux/transcode trae UN solo audio (el servido): exponer solo el
    /// engine escondería el resto ("a veces faltan pistas"). Cada fila
    /// servidor lleva su `serverIndex`; la fila servida además su
    /// `engineIndex` para selección directa. Sin metadata servidor, expone el
    /// engine tal cual (comportamiento anterior).
    /// Internal para tests (el orden/mapeo de la unión es contrato).
    func unionAudioTracks(engineTracks: [AudioTrack]) -> [AudioTrack] {
        let server = serverStreams(type: "Audio")
        guard !server.isEmpty else {
            return engineTracks.enumerated().map { i, track in
                let display = TrackNaming.display(
                    rawName: track.name,
                    languageCode: track.language,
                    serverTitle: nil,
                    index: i,
                    fallbackPrefix: "Audio"
                )
                return AudioTrack(
                    id: i,
                    name: display.title,
                    language: track.language,
                    languageName: display.caption,
                    engineIndex: track.engineIndex ?? track.id
                )
            }
        }

        // engine → posición en `server`.
        var engineToServer: [Int: Int] = [:]
        if engineTracks.count == server.count {
            for i in engineTracks.indices { engineToServer[i] = i }
        } else if let served = servedAudioServerIndex,
                  let pos = server.firstIndex(where: { $0.index == served }),
                  let first = engineTracks.indices.first {
            // Caso típico remux/transcode: la única opción engine ES la servida.
            engineToServer[first] = pos
        }
        // Opciones engine extra sin contraparte: selección nativa directa.
        var out: [AudioTrack] = []
        for (pos, stream) in server.enumerated() {
            let engIdx = engineToServer.first(where: { $0.value == pos })?.key
            let engTrack = engIdx.flatMap { engineTracks.indices.contains($0) ? engineTracks[$0] : nil }
            let display = TrackNaming.display(
                rawName: engTrack?.name,
                languageCode: stream.language ?? engTrack?.language,
                serverTitle: stream.displayTitle ?? stream.title,
                index: pos,
                fallbackPrefix: "Audio"
            )
            out.append(AudioTrack(
                id: out.count,
                name: display.title,
                language: stream.language ?? engTrack?.language,
                languageName: display.caption,
                serverIndex: stream.index,
                engineIndex: engIdx.flatMap { engineTracks.indices.contains($0) ? (engineTracks[$0].engineIndex ?? $0) : nil }
            ))
        }
        for (eIdx, track) in engineTracks.enumerated() where engineToServer[eIdx] == nil {
            let display = TrackNaming.display(
                rawName: track.name,
                languageCode: track.language,
                serverTitle: nil,
                index: out.count,
                fallbackPrefix: "Audio"
            )
            out.append(AudioTrack(
                id: out.count,
                name: display.title,
                language: track.language,
                languageName: display.caption,
                engineIndex: track.engineIndex ?? eIdx
            ))
        }
        return out
    }

    /// All subtitles (both embedded and external) are served by the overlay list with 0-based IDs.
    private func displayExternalSubs() -> [SubtitleTrack] {
        externalSubs.map { $0.track }
    }

    /// Server streams of one type in embedding order: embedded tracks
    /// (container/index order) first, external files after.
    private func serverStreams(type: String) -> [MediaStream] {
        let streams = serverMediaStreams.filter { $0.type == type }
        let embedded = streams.filter { $0.isExternal != true }.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        let external = streams.filter { $0.isExternal == true }.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        return embedded + external
    }

    /// Apply language preferences once per item, honoring a manual choice first.
    ///
    /// Subtitle auto-pick is metadata-ranked (`SubtitleSelection`): among the
    /// server streams matching the wanted language, full dialogue tracks win
    /// over forced-only and non-SDH wins over SDH/CC. Nothing is filtered by
    /// TEXT — every track stays manually selectable.
    private func applyLanguagePreferences() async {
        let prefs = LanguagePreferences.current()
        // Never configured (`nil`) → follow the system language.
        let preferredAudio = prefs.preferredAudio ?? LanguagePreferences.systemDefault
        let preferredSubtitles = prefs.preferredSubtitles ?? LanguagePreferences.systemDefault

        if selectedAudioTrackIndex == nil,
           let audio = LanguagePreferences.selectTrack(
               in: availableAudioTracks,
               preferred: preferredAudio,
               language: { $0.language }
           ) {
            if let engineIdx = audio.engineIndex {
                TJFLog("langPref audio -> id=\(audio.id) lang=\(audio.language ?? "-")")
                await engine.selectAudioTrack(index: engineIdx)
                selectedAudioTrackIndex = audio.id
            } else if audio.serverIndex == servedAudioServerIndex {
                // Fila solo-servidor que YA suena (remux/transcode con el
                // preferido pre-resuelto): solo marcar el checkmark.
                selectedAudioTrackIndex = audio.id
            } else {
                // Fila solo-servidor que NO suena: no marcar (mentiría el
                // checkmark) ni auto re-request (la pre-resolución del plan
                // ya eligió al pedir el stream). Cambio manual vía picker.
                TJFLog("langPref audio: server-only non-served id=\(audio.id) — leaving served stream")
            }
        }

        // Explicit manual off survives episode swaps — never auto-enable.
        if manualSubtitlesOff {
            TJFLog("langPref subtitles: manual off — staying off")
            return
        }
        guard !subtitleSelectionLocked, selectedSubtitleTrackIndex == nil else { return }

        // Manual language (same-language re-pick across episodes) wins over
        // the stored profile preference.
        let wanted = manualSubtitleLanguage ?? preferredSubtitles
        guard let wanted, !wanted.isEmpty else { return }
        guard let pick = pickBestOverlayTrack(preferred: wanted) else {
            TJFLog("langPref subtitles: no match for \(wanted) among \(availableSubtitleTracks.count) tracks")
            return
        }
        TJFLog("langPref subtitles -> id=\(pick.id) lang=\(pick.language ?? "-") forced=\(pick.isForced) sdh=\(pick.isHearingImpaired) wanted=\(wanted)")
        await applySubtitleSelection(pick)
    }

    /// Best overlay track for `preferred` using server stream metadata.
    /// Maps the ranked server stream back to its overlay id via
    /// `externalSubServerIndices` — never reuses a stale per-episode id.
    private func pickBestOverlayTrack(preferred: String) -> SubtitleTrack? {
        // Overlay tracks mirror a subset of server subtitle streams (text
        // formats with parseable cues). Rank at the STREAM level so forced /
        // SDH / default flags decide, then map to the overlay track built
        // from that stream.
        let subStreams = serverMediaStreams.filter { $0.type == "Subtitle" }
        guard let streamIdx = SubtitleSelection.bestStreamIndex(in: subStreams, preferred: preferred) else { return nil }
        let pickedStream = subStreams[streamIdx]
        // Prefer the overlay track built from this exact server stream.
        if let serverIndex = pickedStream.index,
           let overlayIdx = externalSubServerIndices.firstIndex(where: { $0 == serverIndex }) {
            return externalSubs[overlayIdx].track
        }
        // Fallback: first overlay track whose language matches (stream-level
        // flags unavailable, e.g. sidecar added post-load).
        return availableSubtitleTracks.first {
            LanguagePreferences.matches(preferred: preferred, trackLanguage: $0.language)
        }
    }

    /// Server-side external subtitle files (.srt next to the video) are NOT
    /// inside the container AVPlayer parses. Download them, parse locally and
    /// render through the SwiftUI overlay — the server converts any text
    /// format to SRT on request (`/Subtitles/{i}/Stream.srt`).
    private func addExternalSubtitlesIfNeeded() async {
        // Don't consume the flag before the streams are actually configured.
        guard !externalSubsLoaded, !serverMediaStreams.isEmpty else { return }
        guard reportingConfigured, let itemId, let serverURL, let token else { return }
        externalSubsLoaded = true
        let gen = subtitleGeneration

        // Bitmap (PGS/VobSub/DVB): sin texto convertible a SRT; fuera del
        // overlay y con la nativa permanentemente apagada en fullscreen.
        let candidates = serverMediaStreams.filter { stream in
            guard stream.type == "Subtitle" else { return false }
            return !PlaybackStreamPicker.bitmapCodecs.contains((stream.codec ?? "").lowercased())
        }
        guard !candidates.isEmpty else {
            TJFLog("extSubs: server declares none")
            return
        }
        // Descarga CONCURRENTE (antes secuencial: N pistas × RTT dejaba el
        // picker vacío durante segundos tras cada cambio de episodio).
        // Cada pista lleva timeout propio; el padre publica una sola vez en
        // orden de servidor para que los ids del overlay sean estables.
        // Los fallos de texto se indexan (reintento desde el picker) en vez
        // de desaparecer en silencio.
        let (fetched, failed): ([(order: Int, stream: MediaStream, cues: [SubtitleCue])], [Int]) = await withTaskGroup(
            of: (Int, MediaStream, [SubtitleCue]?).self
        ) { group in
            for (i, stream) in candidates.enumerated() {
                guard let idx = stream.index else { continue }
                group.addTask {
                    // Siempre SRT: el servidor convierte ASS/SSA/VTT al vuelo
                    // y SRTParser solo habla SRT (ahora también limpia
                    // restos de formato ASS).
                    guard let cues = await self.downloadSubtitleCues(serverIndex: idx) else {
                        return (i, stream, nil)
                    }
                    return (i, stream, cues)
                }
            }
            var loaded: [(Int, MediaStream, [SubtitleCue])] = []
            var failed: [Int] = []
            for await result in group {
                if let cues = result.2 {
                    loaded.append((result.0, result.1, cues))
                } else if let idx = result.1.index {
                    failed.append(idx)
                }
            }
            // Estado de fallos por generación: un reintento posterior parte
            // de cero en vez de acumular índices obsoletos.
            return (
                loaded.map { (order: $0.0, stream: $0.1, cues: $0.2) },
                failed
            )
        }
        // Swap durante la descarga: el nuevo item tiene listas propias —
        // nunca publicar pistas del anterior.
        guard gen == subtitleGeneration, !engineStopped else {
            TJFLog("extSubs: stale results dropped after fetch (episode changed)")
            return
        }
        failedSubtitleServerIndices = Set(failed)
        for entry in fetched.sorted(by: { $0.order < $1.order }) {
            appendOverlayTrack(stream: entry.stream, order: entry.order, cues: entry.cues)
        }
        refreshUnavailableSubtitleTracks()
        if !externalSubs.isEmpty {
            availableSubtitleTracks = displayExternalSubs()
            await applyLanguagePreferences()
            // PiP may already be active for the new item (auto-start on
            // background during a swap): mirror the fresh selection natively.
            #if os(iOS)
            if PipCoordinator.shared.isWindowActive {
                applyPiPSubtitleMode(active: true)
            }
            #endif
        }
    }

    /// Descarga y parsea UNA pista de texto como SRT (el servidor convierte
    /// ASS/SSA/VTT al vuelo). Nil = fallo reintentable (HTTP≠200, timeout,
    /// ilegible, 0 cues); cada causa queda en log con su índice.
    private func downloadSubtitleCues(serverIndex idx: Int) async -> [SubtitleCue]? {
        guard reportingConfigured, let itemId, let serverURL, let token else { return nil }
        let urlString = "\(serverURL.absoluteString)/Videos/\(itemId)/\(itemId)/Subtitles/\(idx)/Stream.srt?api_key=\(token)"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                TJFLog("extSubs idx=\(idx) HTTP \(http.statusCode)")
                return nil
            }
            guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
            else {
                TJFLog("extSubs idx=\(idx) undecodable — retryable from picker")
                return nil
            }
            let cues = SRTParser.parse(text)
            guard !cues.isEmpty else {
                TJFLog("extSubs idx=\(idx) parsed 0 cues — skipped")
                return nil
            }
            TJFLog("extSubs idx=\(idx) cues=\(cues.count)")
            return cues
        } catch {
            TJFLog("extSubs idx=\(idx) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Construye la fila overlay de un stream servido y la añade manteniendo
    /// el paralelo `externalSubServerIndices` (id posicional == posición).
    private func appendOverlayTrack(stream: MediaStream, order: Int, cues: [SubtitleCue]) {
        let display = TrackNaming.display(
            rawName: stream.displayTitle ?? stream.title ?? "Subtítulo \(order + 1)",
            languageCode: stream.language,
            serverTitle: stream.displayTitle ?? stream.title,
            index: order
        )
        // Surface server flags in the caption so same-language tracks
        // are distinguishable (full vs forced vs SDH). Title stays
        // untouched; flags never hide a track.
        var captionParts: [String] = []
        if let caption = display.caption, !caption.isEmpty { captionParts.append(caption) }
        if stream.isForced == true { captionParts.append("Forzados") }
        if stream.isHearingImpaired == true { captionParts.append("SDH") }
        let track = SubtitleTrack(
            id: externalSubs.count,
            name: display.title,
            language: stream.language,
            languageName: captionParts.isEmpty ? nil : captionParts.joined(separator: " · "),
            isExternal: true,
            isForced: stream.isForced == true,
            isHearingImpaired: stream.isHearingImpaired == true,
            isDefault: stream.isDefault == true
        )
        externalSubs.append((track: track, cues: cues))
        externalSubServerIndices.append(stream.index)
    }

    /// Clasifica las pistas de subtítulo declaradas sin fila overlay:
    /// bitmap → burn-in vía transcode; texto fallido → reintento.
    /// Las aún cargando se omiten (evita parpadeo). Pura → testeable.
    static func classifyUnservedSubtitles(
        serverStreams: [MediaStream],
        loadedServerIndices: Set<Int>,
        failedServerIndices: Set<Int>
    ) -> [UnavailableSubtitleTrack] {
        let subs = serverStreams.filter { $0.type == "Subtitle" }
        var out: [UnavailableSubtitleTrack] = []
        for (pos, stream) in subs.enumerated() {
            guard let idx = stream.index, !loadedServerIndices.contains(idx) else { continue }
            let display = TrackNaming.display(
                rawName: stream.displayTitle ?? stream.title,
                languageCode: stream.language,
                serverTitle: stream.displayTitle ?? stream.title,
                index: pos,
                fallbackPrefix: "Subtítulo"
            )
            var captionParts: [String] = []
            if let caption = display.caption, !caption.isEmpty { captionParts.append(caption) }
            if stream.isForced == true { captionParts.append("Forzados") }
            if stream.isHearingImpaired == true { captionParts.append("SDH") }
            if PlaybackStreamPicker.bitmapCodecs.contains((stream.codec ?? "").lowercased()) {
                captionParts.append((stream.codec ?? "IMG").uppercased())
                out.append(UnavailableSubtitleTrack(
                    id: idx,
                    name: display.title,
                    languageName: captionParts.joined(separator: " · "),
                    codec: stream.codec?.uppercased(),
                    reason: .bitmapRequiresTranscode
                ))
            } else if failedServerIndices.contains(idx) {
                out.append(UnavailableSubtitleTrack(
                    id: idx,
                    name: display.title,
                    languageName: captionParts.isEmpty ? nil : captionParts.joined(separator: " · "),
                    codec: stream.codec?.uppercased(),
                    reason: .downloadFailed
                ))
            }
        }
        return out.sorted { $0.id < $1.id }
    }

    /// Recalcula las filas no disponibles del picker. Internal para tests.
    func refreshUnavailableSubtitleTracks() {
        let loaded = Set(externalSubServerIndices.compactMap { $0 })
        unavailableSubtitleTracks = Self.classifyUnservedSubtitles(
            serverStreams: serverMediaStreams,
            loadedServerIndices: loaded,
            failedServerIndices: failedSubtitleServerIndices
        )
    }

    /// Reintento manual de una pista de texto fallida: la añade al overlay
    /// sin tocar playback. Sin carrera con `addExternal` (misma generación
    /// o item distinto → aborta).
    func retrySubtitleDownload(serverIndex idx: Int) async {
        guard !engineStopped, reportingConfigured else { return }
        guard !externalSubServerIndices.contains(where: { $0 == idx }) else {
            refreshUnavailableSubtitleTracks()
            return
        }
        guard let stream = serverMediaStreams.first(where: { $0.type == "Subtitle" && $0.index == idx }) else { return }
        let gen = subtitleGeneration
        guard let cues = await downloadSubtitleCues(serverIndex: idx) else {
            failedSubtitleServerIndices.insert(idx)
            refreshUnavailableSubtitleTracks()
            return
        }
        guard gen == subtitleGeneration, !engineStopped else { return }
        let order = serverMediaStreams.filter { $0.type == "Subtitle" }.firstIndex(where: { $0.index == idx })
            ?? externalSubs.count
        appendOverlayTrack(stream: stream, order: order, cues: cues)
        failedSubtitleServerIndices.remove(idx)
        availableSubtitleTracks = displayExternalSubs()
        refreshUnavailableSubtitleTracks()
        TJFLog("extSubs idx=\(idx) retry OK cues=\(cues.count)")
    }

    /// Late-arriving server streams for the CURRENT item (episode-swap prop
    /// updates that land after `streamURL`). Refreshes the overlay lists
    /// without touching playback — fixes swaps that kept the old episode's
    /// (or empty) subtitle state forever.
    func refreshMediaStreams(_ streams: [MediaStream]) {
        guard !engineStopped else { return }
        // Same content: nothing to do (avoids re-fetch loops from repeated
        // SwiftUI updates).
        guard streams != serverMediaStreams else { return }
        TJFLog("refreshMediaStreams: \(serverMediaStreams.count) -> \(streams.count)")
        serverMediaStreams = streams
        // New streams for the same item: reload overlay tracks once.
        // Limpia fallos/no-disponibles del estado anterior (se recalculan).
        externalSubsLoaded = false
        failedSubtitleServerIndices = []
        unavailableSubtitleTracks = []
        tracksLoaded = false
        trackLoadAttempts = 0
        Task { await addExternalSubtitlesIfNeeded() }
    }

    // MARK: - Remote subtitle search + download (P6)

    /// Default search language: profile preference, else system language.
    func defaultRemoteSubtitleLanguage() -> String {
        let prefs = LanguagePreferences.current()
        if let pref = prefs.preferredSubtitles, !pref.isEmpty { return pref }
        return LanguagePreferences.systemDefault ?? "es"
    }

    /// Search server providers. Never touches playback — results land in
    /// `remoteSubtitleResults` for the sheet. Empty = no provider configured
    /// server-side or no match (surfaced as helper text, not an error).
    func searchRemoteSubtitles() async {
        guard !isSearchingRemoteSubs,
              let serverURL, let token, let itemId else { return }
        let language = remoteSubtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !language.isEmpty else {
            remoteSubtitleError = SubtitleSearchError.invalidLanguage.localizedDescription
            return
        }
        isSearchingRemoteSubs = true
        remoteSubtitleError = nil
        defer { isSearchingRemoteSubs = false }
        do {
            remoteSubtitleResults = try await subtitleClient.searchRemoteSubtitles(
                serverURL: serverURL, token: token, itemId: itemId, language: language
            )
            remoteSubsSearched = true
            if remoteSubtitleResults.isEmpty {
                TJFLog("subsearch: no results (server may have no subtitle provider configured)")
            }
        } catch {
            remoteSubtitleError = error.localizedDescription
            TJFLog("subsearch failed: \(error.localizedDescription)")
        }
    }

    /// Download one remote result server-side, then load the NEW file into
    /// the overlay and select it — without recreating the player item, so
    /// playback (and PiP) continue uninterrupted.
    func downloadAndSelectRemoteSubtitle(_ result: RemoteSubtitleInfo) async {
        guard downloadingRemoteSubtitleId == nil,
              let userId, let serverURL, let token, let itemId else { return }
        downloadingRemoteSubtitleId = result.id
        remoteSubtitleError = nil
        defer { downloadingRemoteSubtitleId = nil }
        do {
            try await subtitleClient.downloadRemoteSubtitle(
                serverURL: serverURL, token: token, itemId: itemId, subtitleId: result.id
            )
            // The sidecar is new server-side: refresh ONLY the stream list
            // (keep the current URL + PlaySessionId — no re-prepare, no stop).
            // Subs siempre -1 (invariante anti-dobles); se preserva el audio.
            let info = try await JellyfinPlaybackClient().fetchPlaybackInfo(
                userId: userId, serverURL: serverURL, token: token, itemId: itemId,
                deviceProfile: .avPlayer.capped(to: selectedQuality.maxBitrate),
                maxStreamingBitrate: selectedQuality.maxBitrate,
                subtitleStreamIndex: -1,
                audioStreamIndex: servedAudioServerIndex
            )
            guard let source = info.mediaSources.first else {
                remoteSubtitleError = "El servidor no devolvió fuentes tras la descarga."
                return
            }
            let knownIndices = Set(serverMediaStreams.compactMap(\.index))
            let fresh = source.mediaStreams.filter { stream in
                guard stream.type == "Subtitle", let idx = stream.index else { return false }
                return !knownIndices.contains(idx)
            }
            guard !fresh.isEmpty else {
                remoteSubtitleError = "Descargado, pero el servidor no expuso el archivo nuevo. Reintenta en unos segundos."
                return
            }
            serverMediaStreams = source.mediaStreams
            var selected: SubtitleTrack?
            for stream in fresh {
                if let track = await fetchRemoteSideloadedTrack(stream) {
                    selected = track
                }
            }
            availableSubtitleTracks = displayExternalSubs()
            if let selected {
                subtitleSelectionLocked = true
                await applySubtitleSelection(selected)
            }
        } catch {
            remoteSubtitleError = error.localizedDescription
            TJFLog("subsearch download failed: \(error.localizedDescription)")
        }
    }

    /// Fetch one freshly-downloaded sidecar as SRT and append it to the overlay.
    /// Returns the new track (nil when the file has no parseable cues).
    private func fetchRemoteSideloadedTrack(_ stream: MediaStream) async -> SubtitleTrack? {
        guard let idx = stream.index,
              let itemId, let serverURL, let token else { return nil }
        let urlString = "\(serverURL.absoluteString)/Videos/\(itemId)/\(itemId)/Subtitles/\(idx)/Stream.srt?api_key=\(token)"
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else { return nil }
            let cues = SRTParser.parse(text)
            guard !cues.isEmpty else {
                TJFLog("subsearch: downloaded file parsed 0 cues — skipped")
                return nil
            }
            let display = TrackNaming.display(
                rawName: stream.displayTitle ?? stream.title ?? "Subtítulo \(externalSubs.count + 1)",
                languageCode: stream.language,
                serverTitle: stream.displayTitle ?? stream.title,
                index: externalSubs.count
            )
            let track = SubtitleTrack(
                id: externalSubs.count,
                name: display.title,
                language: stream.language,
                languageName: display.caption,
                isExternal: true
            )
            externalSubs.append((track: track, cues: cues))
            return track
        } catch {
            TJFLog("subsearch: sidecar fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Playback Reporting

    private func reportPlayStarted() {
        guard let userId, let serverURL, let token, let itemId else {
            TJFLog("reportPlayStarted SKIPPED: userId=\(userId != nil) serverURL=\(serverURL != nil) token=\(token != nil) itemId=\(itemId != nil)")
            return
        }
        let mediaSourceId = itemId
        TJFLog("reportPlayStarted itemId=\(itemId)")
        Task {
            await reporter.reportPlaying(
                userId: userId, serverURL: serverURL, token: token,
                itemId: itemId, mediaSourceId: mediaSourceId
            )
        }
    }

    private func reportProgress() {
        reportProgress(at: currentTime)
    }

    private func reportProgress(at position: Double) {
        guard let userId, let serverURL, let token, let itemId else {
            TJFLog("reportProgress SKIPPED: userId=\(userId != nil) serverURL=\(serverURL != nil) token=\(token != nil) itemId=\(itemId != nil)")
            return
        }
        // Never report below an unfulfilled resume target, and never report 0:
        // the server treats any reported position as authoritative and would
        // overwrite the saved resume point (seen in device logs).
        let effective = max(position, pendingResumePosition ?? 0)
        let ticks = Int64(effective * 10_000_000) // 1 tick = 100ns
        guard ticks > 0 else {
            TJFLog("reportProgress SKIPPED: position=0 (preserves saved resume)")
            return
        }
        lastProgressReport = Date()
        // Release the resume pin ONLY once real playback reached it.
        if let target = pendingResumePosition, position >= target - 2.0 {
            pendingResumePosition = nil
        }
        TJFLog("reportProgress itemId=\(itemId) ticks=\(ticks)")
        Task {
            await reporter.reportProgress(
                userId: userId, serverURL: serverURL, token: token,
                itemId: itemId, mediaSourceId: itemId,
                positionTicks: ticks, isPaused: !isPlaying
            )
        }
    }

    /// - Returns: true when a stop report was actually queued.
    @discardableResult
    private func reportStopped() -> Bool {
        guard let userId, let serverURL, let token, let itemId else {
            TJFLog("reportStopped SKIPPED: userId=\(userId != nil) serverURL=\(serverURL != nil) token=\(token != nil) itemId=\(itemId != nil)")
            return false
        }
        // Same rule as progress: an exit during a stalled open must not send
        // PositionTicks:0 — it wipes the server's saved resume position.
        let effective = max(currentTime, pendingResumePosition ?? 0)
        let ticks = Int64(effective * 10_000_000)
        guard ticks > 0 else {
            TJFLog("reportStopped SKIPPED: position=0 (preserves saved resume)")
            return false
        }
        TJFLog("reportStopped itemId=\(itemId) ticks=\(ticks)")
        Task {
            await reporter.reportStopped(
                userId: userId, serverURL: serverURL, token: token,
                itemId: itemId, mediaSourceId: itemId,
                positionTicks: ticks
            )
        }
        return true
    }

    func stop() async {
        reportStopped()
        stopReported = true
        engine.stop()
        stopUpdating()
    }

    // MARK: - Handoff takeover

    /// Ask the server who is playing what (GET /Sessions). NSUserActivity is
    /// one-way — after the continuation lands on the receiver there is no
    /// push channel back — so polling is the only signal that a handoff moved
    /// playback to another device. Wired to the 0.5 s tick (every 10th tick).
    func checkHandoffTakeover() async {
        guard !receivedViaHandoff,
              handoffTakeoverDeviceName == nil,
              !takeoverCheckInFlight,
              !stopReported,
              !engineStopped,
              reportingConfigured,
              let serverURL, let token, let itemId
        else { return }
        #if os(iOS)
        // Cast: the local engine is already idle and the remote session is
        // CastController's, not a Jellyfin device taking playback away.
        if isCastEmitting { return }
        #endif
        takeoverCheckInFlight = true
        defer { takeoverCheckInFlight = false }

        do {
            let sessions = try await sessionClient.fetchActiveSessions(
                serverURL: serverURL, token: token
            )
            // Admin accounts see EVERY user's sessions — only our own user's
            // sessions can be a handoff takeover of our playback.
            let ownUserSessions = sessions.filter { $0.userId == nil || $0.userId == userId }
            guard let taker = ActiveSessionInfo.takeoverSource(
                in: ownUserSessions,
                ourDeviceId: DeviceIdentifier().current(),
                itemId: itemId
            ) else { return }
            applyHandoffTakeover(taker)
        } catch {
            TJFLog("handoff takeover check FAILED: \(error.localizedDescription)")
        }
    }

    /// Another device is actively playing our item: go dark HERE. First clear
    /// our own /Sessions claim (the new owner runs the same check and must
    /// never see our stale entry as a takeover source), then tear down.
    private func applyHandoffTakeover(_ taker: ActiveSessionInfo) {
        let name = taker.deviceName ?? "otro dispositivo"
        handoffTakeoverDeviceName = name
        TJFLog("handoff takeover: '\(name)' (deviceId=\(taker.deviceId ?? "?")) now plays item=\(itemId ?? "?") — this device goes dark")
        reportStopped()
        stopReported = true
        #if os(iOS)
        // A floating window must not outlive the takeover either.
        if PipCoordinator.shared.isWindowActive {
            PipCoordinator.shared.stop()
        }
        #endif
        stopSync(reportStop: true)
    }

    /// Synchronous stop — call from onDisappear to guarantee the engine stops
    /// before the view is deallocated.
    /// - Parameter reportStop: false when playback continues in the floating
    ///   PiP window — this view model keeps reporting progress on its own.
    func stopSync(reportStop: Bool = true) {
        #if os(iOS)
        // Emisión Cast: la sesión vive en CastController (singleton) y su
        // reporter es el único autoridad de posición. Un stop local aquí
        // marcaría el ítem como visto parado mientras el Chromecast sigue.
        if isCastEmitting {
            TJFLog("cast: view exit — la emisión continúa vía CastController")
            engine.stopSync()
            stopUpdating()
            engineStopped = true
            // El lock-screen pasa a describir la emisión remota gestionada
            // por CastController; los comandos del sistema ya no deben caer
            // en este VM muerto.
            if nowPlayingActive {
                nowPlayingActive = false
                NowPlayingController.shared.deactivate(session: nowPlayingSession)
                nowPlayingSession = nil
            }
            return
        }
        #endif
        if reportStop && !stopReported {
            // Only latch when a stop was actually sent — reportStopped skips
            // the POST at position 0 (to preserve the saved resume), and that
            // case must not block a later, real stop.
            stopReported = reportStopped()
        }
        engine.stopSync()
        #if !os(visionOS)
        // Teardown ends any pending handoff — no stale "connecting" status.
        airplayPhase = nil
        airplayMessage = nil
        #endif
        stopUpdating()
        engineStopped = true
        // Playback is over (not a PiP handoff — that never reaches stopSync):
        // clear the lock screen, stop answering remote commands and hand
        // Handoff back to the browsing activity.
        if nowPlayingActive {
            nowPlayingActive = false
            NowPlayingController.shared.deactivate(session: nowPlayingSession)
            nowPlayingSession = nil
        }
        HandoffCenter.shared.setPlaybackActive(false)
    }

    // MARK: - Picture in Picture (iOS)

    #if os(iOS)
    /// The system window is up (or starting).
    var isPipWindowActive: Bool { PipCoordinator.shared.isWindowActive }
    /// PlayerView sets this so a user-closed PiP window dismisses fullscreen UI.
    var onPiPClosed: (() -> Void)?

    /// Context for the root view to rebuild the fullscreen player while this
    /// VM floats. nil → float is refused (nothing to restore).
    func makePipContext() -> PipContext? {
        guard let itemId, let serverURL, let token, let userId,
              let streamURL = currentStreamURL
        else { return nil }
        return PipContext(
            itemId: itemId,
            serverURL: serverURL,
            token: token,
            userId: userId,
            playSessionId: reportingSessionId,
            streamURL: streamURL,
            title: playbackTitle,
            mediaStreams: serverMediaStreams
        )
    }

    /// Manual PiP start (controls button) / safety-net start.
    /// - Returns: true when the window is active or the start was issued.
    ///   Subtitle selection never recreates the player item, so calling this
    ///   after a track change keeps the same AVPlayer/AVPlayerLayer wiring.
    func startPictureInPicture() async -> Bool {
        guard !engineStopped else { return false }
        PipCoordinator.shared.configure(engine: engine)
        return PipCoordinator.shared.start()
    }

    /// Take playback back from the window (pip.exit button) — same player,
    /// no re-prepare: the window just closes and fullscreen keeps playing.
    func resumeFromPictureInPicture() async {
        guard PipCoordinator.shared.isWindowActive else { return }
        TJFLog("pip: exit button → closing window")
        PipCoordinator.shared.stop()
    }

    /// Wire this VM as the on-screen player for window-close events.
    func attachPipHandlers() {
        PipCoordinator.shared.liveVM = self
    }

    /// Unregister — the float path keeps ownership via `floatingVM`.
    func detachPipHandlers() {
        if PipCoordinator.shared.liveVM === self {
            PipCoordinator.shared.liveVM = nil
        }
    }

    /// Language of the currently selected overlay track (nil = off).
    /// PiP mirrors THIS language natively — never a different one.
    var pipSubtitleLanguage: String? {
        guard let idx = selectedExternalSubIndex, idx < externalSubs.count else { return nil }
        return externalSubs[idx].track.language
    }

    /// Switch the subtitle renderer for PiP WITHOUT touching PiP itself.
    ///
    /// - active=true (window started): enable the embedded native option
    ///   matching the overlay selection so the system window shows subs.
    /// - active=false (window stopped/restored): clear native again — the
    ///   fullscreen overlay is the single renderer once more.
    /// No-ops when subs are off or the engine is dead; never invents a
    /// language when there is no native match (engine stays clear).
    func applyPiPSubtitleMode(active: Bool) {
        guard !engineStopped else { return }
        engine.setPiPSubtitleMode(active: active, language: active ? pipSubtitleLanguage : nil)
    }
    #endif

    /// The fullscreen view disappeared. Playback must NOT die with it: hand
    /// the running item to the floating window when possible, otherwise stop.
    func handleViewExit(handoffAllowed: Bool = true) {
        #if os(iOS)
        if errorMessage != nil {
            // An error path tore this player down: a floating window over an
            // error screen keeps a broken session alive with nobody watching.
            TJFLog("pip: exit after error → stop with report, no handoff")
            stopSync(reportStop: true)
            return
        }
        if handoffAllowed, canAutoHandoffToPiP, reportingConfigured, itemId != nil,
           // The user CLOSED the floating window before: that ended playback.
           !stopReported
        {
            if PipCoordinator.shared.float(self) {
                TJFLog("pip: view exit → floating (reporting continues)")
                // onDisappear stopped the timer before us — the floating VM
                // must keep reporting progress.
                startUpdating()
                return
            }
            TJFLog("pip: float refused → stopping with report")
        }
        #endif
        stopSync(reportStop: true)
    }
}
