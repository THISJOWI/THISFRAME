import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

struct DetailView: View {
    let item: JellyfinMediaItem
    let serverURL: URL
    let token: String
    let userId: String
    var onPlayerDismiss: (() -> Void)? = nil
    /// Handoff: playback position (seconds) published by another device.
    /// Non-nil → start playback automatically (max with server resume) once
    /// the detail loads, instead of just showing the screen.
    var handoffPosition: Double? = nil
    /// F2: called the moment the handoff position has been read for autoplay,
    /// so the shared LibraryModel value dies immediately (a stale one could
    /// otherwise be re-applied to a DIFFERENT destination on identity churn).
    var onHandoffConsumed: (() -> Void)? = nil

    @State private var detail: JellyfinItemDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPlayer = false
    @State private var streamURL: URL?
    @State private var streamTitle: String = ""
    @State private var streamStartPosition: Double?
    @State private var currentItemId: String?
    @State private var currentPlaySessionId: String?
    @State private var currentMediaStreams: [MediaStream] = []
    /// Audio SERVIDO por el plan (`MediaStream.index` pedido o default).
    /// Viaja al PlayerView junto a `mediaStreams` para el mapeo engine↔servidor.
    @State private var currentAudioServerIndex: Int?
    @State private var isPreparingPlayback = false
    @State private var playbackError: String?
    @State private var nextEpisode: JellyfinEpisode?
    @State private var previousEpisode: JellyfinEpisode?
    /// Handoff autoplay fires at most once per DetailView instance — a SwiftUI
    /// rebuild must not restart playback over the user's head.
    @State private var handoffAutoplayStarted = false
    /// true when the CURRENT presented player session started from a received
    /// handoff continuation. Passed to PlayerView: the receiver must never
    /// yield back to the sender's still-active /Sessions entry.
    @State private var startedViaHandoff = false

    // MARK: - Seasons & Episodes
    @State private var seasons: [JellyfinSeason] = []
    @State private var selectedSeasonIndex: Int = 0
    /// First load only: jump to the season that holds the in-progress episode.
    @State private var didChooseInitialSeason = false
    @State private var episodes: [JellyfinEpisode] = []
    @State private var isLoadingEpisodes = false
    /// Message shown when the episode list could not be loaded or refreshed.
    @State private var episodesError: String?

    // MARK: - User flags & technical info
    @State private var isFavorite = false
    @State private var isPlayed = false
    /// One flag per action: a slow or failing request must not lock the whole
    /// pill, and the other action stays usable.
    @State private var isSavingFavorite = false
    @State private var isSavingPlayed = false
    @State private var userActionError: String?
    @State private var videoChips: [VideoChip] = []
    /// Bumped by the episodes button; the `ScrollViewReader` watches it because
    /// `ScrollViewProxy` can't be stored across the toolbar.
    @State private var scrollToEpisodesToken = 0

    private static let episodesAnchor = "episodes"

    /// Media type of what is actually playing: an episode swap changes
    /// `currentItemId` away from the navigated item (series → episode).
    private var playingMediaType: String {
        if let currentItemId, currentItemId != item.id { return "Episode" }
        return detail?.type ?? item.type
    }

    var body: some View {
        #if os(macOS)
        ZStack {
            detailContent
                .navigationTitle("")
                .navigationBarBackButtonHidden(showPlayer)
                .toolbar(showPlayer ? .hidden : .visible, for: .windowToolbar)
                // Action pill: own overlay instead of a toolbar item — no
                // system platter behind it (the "double pill") and exact
                // control of the drop from the titlebar.
                .overlay(alignment: .topTrailing) {
                    if !showPlayer {
                        actionPill
                            .padding(.trailing, 24)
                            .padding(.top, 60)
                    }
                }
                .task { await loadDetailAndMaybeAutoplay() }
                .onChange(of: showPlayer) { _, showing in
                    // Keep the sidebar out of the way while the player covers
                    // the window; restore it (and the previous column value)
                    // the moment the player goes away.
                    if showing {
                        SplitViewState.shared.collapseForPlayer()
                    } else {
                        SplitViewState.shared.restore()
                        onPlayerDismiss?()
                        // The episode we just played changed its state on the
                        // server — the list must show the new progress.
                        if detail?.type == "Series" {
                            Task { await reloadEpisodesAfterPlayback() }
                        }
                    }
                }
                // Ownership: a mounted detail claims the Handoff slot (counted
                // in HandoffCenter for nested stacks). This covers TAP pushes
                // too — push-site tracking missed them (double activity).
                .onAppear { HandoffCenter.shared.setDetailActive(true) }
                .onDisappear {
                    HandoffCenter.shared.setDetailActive(false)
                    // Safety net: if this detail dies while its player is up,
                    // the ZStack goes with it — never leave the sidebar hidden.
                    if showPlayer { SplitViewState.shared.restore() }
                }
                // m4: while this screen is the top one it OWNS the Handoff
                // slot (browsing yields on push, playing yields once the
                // player mounts) — this also makes the receiving
                // `.onContinueUserActivity(detail)` path non-dead.
                .userActivity(
                    HandoffActivity.detail,
                    isActive: HandoffCenter.shared.shouldPublishBrowsing
                ) { activity in
                    let built = HandoffActivity.detailActivity(
                        item: HandoffMediaItem(id: item.id, name: item.name, type: item.type),
                        serverURL: serverURL
                    )
                    activity.title                = built.title
                    activity.isEligibleForHandoff = true
                    activity.isEligibleForSearch  = false
                    activity.userInfo             = built.userInfo
                    activity.requiredUserInfoKeys  = built.requiredUserInfoKeys
                    activity.targetContentIdentifier = built.targetContentIdentifier
                }

            if showPlayer, let streamURL {
                PlayerView(
                    streamURL: streamURL,
                    title: streamTitle,
                    startPosition: streamStartPosition,
                    onDismiss: { withAnimation { showPlayer = false } },
                    itemId: currentItemId,
                    serverURL: serverURL,
                    token: token,
                    userId: userId,
                    mediaType: playingMediaType,
                    playSessionId: currentPlaySessionId,
                    mediaStreams: currentMediaStreams,
                    audioServerIndex: currentAudioServerIndex,
                    nextEpisode: nextEpisode,
                    onPlayNextEpisode: { episode in
                        Task { await playNextEpisode(episode) }
                    },
                    onPlaybackCompleted: {
                        // The server now owns the final state. Re-read the
                        // rows while the player is still mounted so leaving
                        // it never shows the pre-playback progress.
                        if detail?.type == "Series" {
                            Task { await reloadEpisodesAfterPlayback() }
                        }
                    },
                    previousEpisode: previousEpisode,
                    onPlayPreviousEpisode: { episode in
                        Task { await playEpisode(episode) }
                    },
                    subtitle: playerSubtitle,
                    receivedViaHandoff: startedViaHandoff
                )
                .ignoresSafeArea()
            }
        }
        #else
        detailContent
            .navigationTitle("")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationBarBackButtonHidden(showPlayer)
            .fullScreenCover(isPresented: $showPlayer) {
                if let streamURL {
                    PlayerView(
                        streamURL: streamURL,
                        title: streamTitle,
                        startPosition: streamStartPosition,
                        onDismiss: {
                            withAnimation { showPlayer = false }
                        },
                        itemId: currentItemId,
                        serverURL: serverURL,
                        token: token,
                        userId: userId,
                        mediaType: playingMediaType,
                        playSessionId: currentPlaySessionId,
                        mediaStreams: currentMediaStreams,
                        audioServerIndex: currentAudioServerIndex,
                        nextEpisode: nextEpisode,
                        onPlayNextEpisode: { episode in
                            Task { await playNextEpisode(episode) }
                        },
                        onPlaybackCompleted: {
                            // The server now owns the final state. Re-read the
                            // rows while the player is still mounted so leaving
                            // it never shows the pre-playback progress.
                            if detail?.type == "Series" {
                                Task { await reloadEpisodesAfterPlayback() }
                            }
                        },
                        previousEpisode: previousEpisode,
                        onPlayPreviousEpisode: { episode in
                            Task { await playEpisode(episode) }
                        },
                        subtitle: playerSubtitle,
                        receivedViaHandoff: startedViaHandoff
                    )
                    .ignoresSafeArea()
                }
            }
            .task { await loadDetailAndMaybeAutoplay() }
            .onChange(of: showPlayer) { _, showing in
                if !showing {
                    onPlayerDismiss?()
                    // The episode we just played changed its state on the
                    // server — the list must show the new progress (or the
                    // "watched" mark) without the user pulling to refresh.
                    if detail?.type == "Series" {
                        Task { await reloadEpisodesAfterPlayback() }
                    }
                }
            }
            // Ownership (iOS mirror): mounted detail claims the slot.
            .onAppear { HandoffCenter.shared.setDetailActive(true) }
            .onDisappear { HandoffCenter.shared.setDetailActive(false) }
            // m4 (iOS mirror): detail owns the Handoff slot at this depth.
            .userActivity(
                HandoffActivity.detail,
                isActive: HandoffCenter.shared.shouldPublishBrowsing
            ) { activity in
                let built = HandoffActivity.detailActivity(
                    item: HandoffMediaItem(id: item.id, name: item.name, type: item.type),
                    serverURL: serverURL
                )
                activity.title                = built.title
                activity.isEligibleForHandoff = true
                activity.isEligibleForSearch  = false
                activity.userInfo             = built.userInfo
                activity.requiredUserInfoKeys  = built.requiredUserInfoKeys
                activity.targetContentIdentifier = built.targetContentIdentifier
            }
        #endif
    }

    private var detailContent: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical, showsIndicators: true) {
                if let detail {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(detail: detail)

                        VStack(alignment: .leading, spacing: 20) {
                            errorBanners

                            if !videoChips.isEmpty {
                                videoSection
                            }

                            if let overview = detail.overview, !overview.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Sinopsis")
                                        .font(.title3.bold())
                                    Text(overview)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            if detail.type == "Series" {
                                episodesSection
                                    .id(Self.episodesAnchor)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .frame(maxWidth: contentMaxWidth, alignment: .leading)

                        // Spacer ensures scroll area extends beyond content
                        Spacer(minLength: 80)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                } else if isLoading {
                    ProgressView("Cargando detalle…")
                        .frame(maxWidth: .infinity, minHeight: 400)
                        .transition(.opacity)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                        Button("Reintentar") { Task { await loadDetail() } }
                            .buttonStyle(.borderedProminent)
                            .tint(MareaTheme.Colors.accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            // The content fades in over the loading state instead of cutting
            // to it — the screen never "jumps" under the reader.
            .mareaAnimation(MareaMotion.fade, value: detail != nil)
            // The hero owns the whole top of the screen; the navigation bar floats
            // above it (hidden background) so the backdrop bleeds under the status bar.
            .ignoresSafeArea(edges: .top)
            .background(MareaTheme.Colors.background.ignoresSafeArea())
            .refreshable {
                // Detail, seasons and episodes in parallel — one gesture, one
                // request each. The content stays on screen while they fly.
                async let detailReload: Void = fetchDetail(reloadSeasons: false)
                async let seasonsReload: Void = loadSeasons()
                _ = await (detailReload, seasonsReload)
            }
            .onChange(of: scrollToEpisodesToken) { _, _ in
                withAnimation { scroller.scrollTo(Self.episodesAnchor, anchor: .top) }
            }
        }
        #if os(iOS) || os(tvOS) || os(visionOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .toolbar {
            // macOS: pill lives in an overlay (see below) — inside the toolbar
            // macOS draws its OWN platter behind the item and the padding to
            // lower it was ignored → "double pill", still glued to the top.
            #if os(iOS) || os(tvOS) || os(visionOS)
            ToolbarItem(placement: .topBarTrailing) {
                actionPill
            }
            #endif
        }
    }

    // MARK: - Navigation bar actions

    /// Secondary actions live in one native menu instead of a row of separate
    /// icons. The primary Play / Continue action stays visible in the hero.
    private var actionPill: some View {
        Menu {
            if let detail {
                if detail.type != "Series" {
                    Button {
                        Task { await playMovie(detail) }
                    } label: {
                        Label(
                            detail.resumePositionSeconds != nil ? "Continuar" : "Reproducir",
                            systemImage: "play.fill"
                        )
                    }
                } else {
                    Button {
                        scrollToEpisodesToken += 1
                    } label: {
                        Label("Episodios", systemImage: "list.bullet")
                    }
                }
                Divider()
            }

            Button {
                togglePlayed()
            } label: {
                Label(
                    isPlayed ? "Marcar como no visto" : "Marcar como visto",
                    systemImage: isPlayed ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .disabled(isSavingPlayed)

            Button {
                toggleFavorite()
            } label: {
                Label(
                    isFavorite ? "Quitar de favoritos" : "Añadir a favoritos",
                    systemImage: isFavorite ? "heart.fill" : "heart"
                )
            }
            .disabled(isSavingFavorite)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
        }
        .accessibilityLabel("Más acciones")
        .actionPillBackground()
    }

    // MARK: - Hero

    private func hero(detail: JellyfinItemDetail) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                backdropImage(detail: detail, width: proxy.size.width)

                // Bottom scrim keeps the title and actions readable on light
                // artwork and melts the image into the content below. The last
                // stop is the app background, so there is no hard seam in
                // either appearance.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.12), location: 0.38),
                        .init(color: .black.opacity(0.62), location: 0.72),
                        .init(color: .black.opacity(0.92), location: 0.9),
                        .init(color: MareaTheme.Colors.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 14) {
                    Text(detail.type == "Series" ? "SERIE" : "PELÍCULA")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.7))

                    Text(detail.name)
                        .font(.system(size: heroTitleSize, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)

                    Text(metadataLine(detail))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)

                    HStack(spacing: MareaTheme.Spacing.sm) {
                        heroPrimaryButton(detail: detail)
                        heroFavoriteButton
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .frame(width: proxy.size.width, height: heroHeight)
            .clipped()
        }
        .frame(height: heroHeight)
    }

    /// Primary hero action: a single, unmistakable capsule. When there is
    /// progress it reads "Continuar" plus the episode and time left, with a
    /// hairline progress bar inside the capsule, so resuming is obvious
    /// without changing what the button actually does.
    private func heroPrimaryButton(detail: JellyfinItemDetail) -> some View {
        Button {
            if detail.type == "Series" {
                continueSeries()
            } else {
                Task { await playMovie(detail) }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 36, height: 36)
                    if isPreparingPlayback {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: heroPrimaryIcon(detail: detail))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(isPreparingPlayback ? "Preparando…" : heroPrimaryLabel(detail: detail))
                        .font(.headline)
                    if !isPreparingPlayback, let line = heroPrimaryDetailLine(detail: detail) {
                        Text(line)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 8)
            .padding(.trailing, 18)
            .padding(.vertical, 7)
            .frame(minWidth: 170, minHeight: 52)
            .background(MareaTheme.Colors.accent, in: Capsule())
            .overlay(alignment: .bottomLeading) {
                if let fraction = heroProgressFraction(detail: detail) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.white.opacity(0.85))
                            .frame(width: max(6, proxy.size.width * fraction), height: 2.5)
                    }
                    .frame(height: 2.5)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                }
            }
            .shadow(color: MareaTheme.Colors.accent.opacity(0.3), radius: 10, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPreparingPlayback)
        .accessibilityHint(heroPrimaryAccessibilityHint(detail: detail))
    }

    /// Second line of the primary capsule: "T1 E5 · 12 min restantes" while
    /// resuming, or just the episode label when starting from the beginning.
    private func heroPrimaryDetailLine(detail: JellyfinItemDetail) -> String? {
        guard detail.type == "Series", let episode = preferredEpisode else { return nil }
        guard let resume = episode.resumePositionSeconds, resume > 0 else {
            return episode.episodeLabel
        }
        guard let duration = episode.durationSeconds, duration > resume else {
            return episode.episodeLabel
        }
        let remaining = max(1, Int((duration - resume) / 60))
        return "\(episode.episodeLabel) · \(remaining) min restantes"
    }

    private func heroProgressFraction(detail: JellyfinItemDetail) -> Double? {
        if detail.type == "Series" {
            guard let episode = preferredEpisode,
                  let resume = episode.resumePositionSeconds, resume > 0,
                  let duration = episode.durationSeconds, duration > 0
            else { return nil }
            return min(max(resume / duration, 0.02), 1)
        }
        guard let resume = detail.resumePositionSeconds, resume > 0,
              let minutes = detail.durationMinutes, minutes > 0
        else { return nil }
        return min(max(resume / (Double(minutes) * 60), 0.02), 1)
    }

    private func heroPrimaryAccessibilityHint(detail: JellyfinItemDetail) -> String {
        if detail.type == "Series", let episode = preferredEpisode {
            if let resume = episode.resumePositionSeconds, resume > 0 {
                return "Reanuda \(episode.episodeLabel) desde donde lo dejaste"
            }
            return "Reproduce \(episode.episodeLabel)"
        }
        if detail.type == "Series" { return "Muestra los episodios de la serie" }
        return detail.resumePositionSeconds != nil ? "Reanuda la reproducción" : "Inicia la reproducción"
    }

    private var heroFavoriteButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Label(
                isFavorite ? "En tu lista" : "Mi lista",
                systemImage: isFavorite ? "heart.fill" : "heart"
            )
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.black.opacity(0.3), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(isSavingFavorite)
    }

    private func heroPrimaryLabel(detail: JellyfinItemDetail) -> String {
        if detail.type == "Series" {
            return preferredEpisode == nil ? "Ver episodios" : (preferredEpisode?.resumePositionSeconds != nil ? "Continuar" : "Reproducir")
        }
        return detail.resumePositionSeconds != nil ? "Continuar" : "Reproducir"
    }

    private func heroPrimaryIcon(detail: JellyfinItemDetail) -> String {
        detail.type == "Series" && preferredEpisode == nil ? "list.bullet" : "play.fill"
    }

    private func metadataLine(_ detail: JellyfinItemDetail) -> String {
        var parts: [String] = []
        if let year = detail.year { parts.append(String(year)) }
        if let rating = detail.officialRating, !rating.isEmpty { parts.append(rating) }
        if let minutes = detail.durationMinutes { parts.append(Self.durationLabel(minutes)) }
        if let genres = detail.genres, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        }
        if parts.isEmpty {
            parts.append(detail.type == "Series" ? "Serie" : "Película")
        }
        return parts.joined(separator: " · ")
    }

    /// The episode a "Continuar" tap should resume: an in-progress episode
    /// first, otherwise the first unwatched one in the selected season.
    private var preferredEpisode: JellyfinEpisode? {
        episodes.first(where: { ($0.resumePositionSeconds ?? 0) > 0 })
            ?? episodes.first(where: { !$0.isPlayed })
    }

    private func continueSeries() {
        guard let episode = preferredEpisode else {
            scrollToEpisodesToken += 1
            return
        }
        Task { await playEpisode(episode) }
    }

    private var heroTitleSize: CGFloat {
        #if os(tvOS)
        52
        #elseif os(macOS) || os(visionOS)
        46
        #else
        36
        #endif
    }

    @ViewBuilder
    private func backdropImage(detail: JellyfinItemDetail, width: CGFloat) -> some View {
        if detail.hasBackdrop {
            let url = serverURL
                .appendingPathComponent("Items/\(detail.id)/Images/Backdrop")
                .appending(queryItems: [
                    URLQueryItem(name: "maxWidth", value: "1600"),
                    URLQueryItem(name: "quality", value: "90"),
                ])

            MareaImageView(
                url: url,
                placeholder: String(detail.name.prefix(1)),
                width: 0,
                height: 0,
                fallbackURL: posterURL(for: detail)
            )
            .frame(width: width, height: heroHeight, alignment: .top)
            .clipped()
            .overlay(
                // Top scrim: legibility for the navigation bar and toolbar pill
                LinearGradient(
                    colors: [.black.opacity(0.6), .black.opacity(0.15), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )
        } else {
            // No backdrop — poster centred on the app's dark card colour.
            ZStack {
                MareaTheme.Colors.heroFallback
                if detail.hasPoster {
                    MareaImageView(url: posterURL(for: detail), width: 160, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(width: width, height: heroHeight)
        }
    }

    private func posterURL(for detail: JellyfinItemDetail) -> URL? {
        guard detail.hasPoster else { return nil }
        return serverURL
            .appendingPathComponent("Items/\(detail.id)/Images/Primary")
            .appending(queryItems: [
                URLQueryItem(name: "maxWidth", value: "200"),
                URLQueryItem(name: "quality", value: "90"),
            ])
    }

    // MARK: - Content sections

    @ViewBuilder
    private var errorBanners: some View {
        if let playbackError {
            errorBanner(playbackError, systemImage: "exclamationmark.triangle.fill", tint: .orange)
        }
        if let userActionError {
            errorBanner(userActionError, systemImage: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private func errorBanner(_ message: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vídeo")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(videoChips) { chip in
                    Label(chip.text, systemImage: chip.systemImage)
                        .font(.subheadline)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(MareaTheme.Colors.overlayFill, in: Capsule())
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Episodes Section (Series)

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Episodios")
                        .font(.title3.bold())
                    if seasons.indices.contains(selectedSeasonIndex) {
                        Text(seasons[selectedSeasonIndex].displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !seasons.isEmpty {
                    Menu {
                        ForEach(Array(seasons.enumerated()), id: \.element.id) { index, season in
                            Button {
                                selectSeason(at: index)
                            } label: {
                                if index == selectedSeasonIndex {
                                    Label(season.displayName, systemImage: "checkmark")
                                } else {
                                    Text(season.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(seasons.indices.contains(selectedSeasonIndex)
                                 ? seasons[selectedSeasonIndex].displayName
                                 : "Temporada")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(MareaTheme.Colors.glass, in: Capsule())
                        .overlay(Capsule().strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingEpisodes)
                    .accessibilityLabel("Seleccionar temporada")
                }
            }

            if seasons.isEmpty && isLoadingEpisodes {
                ProgressView("Cargando temporadas…")
                    .frame(maxWidth: .infinity)
            } else if seasons.isEmpty {
                Text("No se encontraron temporadas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Episode list. The spinner is for the FIRST load only — a
                // refresh keeps the list on screen instead of blanking it.
                if episodes.isEmpty, isLoadingEpisodes {
                    ProgressView("Cargando episodios…")
                        .frame(maxWidth: .infinity)
                } else if episodes.isEmpty {
                    if let episodesError {
                        errorBanner(episodesError, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                    } else {
                        Text("No hay episodios en esta temporada.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(episodes) { episode in
                            EpisodeRow(
                                episode: episode,
                                serverURL: serverURL
                            ) {
                                Task { await playEpisode(episode) }
                            }
                        }
                    }
                    // A failed refresh leaves the list usable and says so.
                    if let episodesError {
                        errorBanner(episodesError, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectSeason(at index: Int) {
        guard seasons.indices.contains(index) else { return }
        selectedSeasonIndex = index
        episodesError = nil
        Task { await loadEpisodes(for: seasons[index]) }
    }

    // MARK: - Playback

    /// Load the detail, then honour a pending Handoff autoplay (once).
    private func loadDetailAndMaybeAutoplay() async {
        // F2: consume the shared position at TASK START — waiting until after
        // loadDetail() left a window where a fast pop carried the stale value
        // to the next destination.
        let handoff = handoffPosition
        if handoff != nil { onHandoffConsumed?() }

        await loadDetail()
        guard let handoff, !handoffAutoplayStarted else { return }
        handoffAutoplayStarted = true

        let serverResume = detail.flatMap { resumeSeconds($0) } ?? item.resumePositionSeconds
        let start = HandoffResolver.effectiveStart(handoff: handoff, serverResume: serverResume)
        TJFLog("handoff: autoplay item=\(item.id) start=\(Int(start)) (handoff=\(Int(handoff)) server=\(serverResume.map(Int.init) ?? -1))")
        streamTitle = detail?.name ?? item.name
        startedViaHandoff = true
        await preparePlayback(itemId: item.id, startPosition: start > 0 ? start : nil)
    }

    private func playMovie(_ detail: JellyfinItemDetail) async {
        streamTitle = detail.name
        // Movies have no episode chain — drop any stale wiring from a
        // previous episode play.
        nextEpisode = nil
        previousEpisode = nil
        startedViaHandoff = false
        await preparePlayback(itemId: item.id, startPosition: resumeSeconds(detail))
    }

    /// Fresh server progress first (it changes while the screen is open),
    /// then whatever the library row carried.
    private func resumeSeconds(_ detail: JellyfinItemDetail) -> Double? {
        detail.resumePositionSeconds ?? item.resumePositionSeconds
    }

    private func preparePlayback(itemId: String, startPosition: Double? = nil) async {
        isPreparingPlayback = true
        playbackError = nil
        currentItemId = itemId
        defer { isPreparingPlayback = false }

        do {
            // Plan con pre-resolución de índices: 1 roundtrip si el default
            // del servidor ya coincide, 2 si hay que pedir audio/sub.
            let quality = StreamQuality.persisted
            let plan = try await resolvePlaybackPlan(
                userId: userId,
                serverURL: serverURL,
                token: token,
                itemId: itemId,
                quality: quality
            )
            TJFLog("playbackInfo: item=\(itemId) quality=\(quality.label)")
            let source = plan.source

            currentPlaySessionId = plan.playSessionId
            currentMediaStreams = source.mediaStreams
            // Audio SERVIDO (pedido o default): el picker lo usa para
            // mapear engine↔servidor sin adivinar por idioma.
            currentAudioServerIndex = plan.audioServerIndex

            // AVPlayer ladder (direct → remux → HLS) + relative paths + ApiKey.
            let url = StreamURLResolver.playbackURL(
                source: source,
                serverURL: serverURL,
                itemId: itemId,
                token: token
            )

            guard let finalURL = url else {
                failPlayback("URL de stream inválida.")
                return
            }

            #if os(iOS)
            // Lock to landscape BEFORE presenting so iOS rotates the cover on entry
            UIApplication.shared.tjf_orientationLock = [.landscapeLeft, .landscapeRight]
            #endif

            streamURL = finalURL
            streamStartPosition = startPosition
            showPlayer = true
        } catch let libraryError as LibraryError where libraryError == .invalidResponse {
            // El plan no trajo fuente (equivale al antiguo guard): mensaje
            // específico en vez del genérico del decoder.
            failPlayback("No hay fuente de reproducción disponible.")
        } catch {
            // A failed next-episode swap must return to the detail screen where
            // the error is visible, instead of stranding a stopped player.
            failPlayback(error.localizedDescription)
        }
    }

    /// Record the failure and tear the player down BECAUSE of it — the flag
    /// tells `PlayerView.onDisappear` to skip the auto-PiP handoff instead of
    /// floating a broken episode over the error screen.
    private func failPlayback(_ message: String) {
        playbackError = message
        PlayerTeardown.noteError()
        showPlayer = false
    }

    private func playEpisode(_ episode: JellyfinEpisode) async {
        streamTitle = episode.displayTitle
        nextEpisode = nextEpisodeAfter(episode)
        previousEpisode = previousEpisodeBefore(episode)
        startedViaHandoff = false
        await preparePlayback(itemId: episode.id, startPosition: episode.resumePositionSeconds)
    }

    /// Next episode in the currently listed season order, if any.
    private func nextEpisodeAfter(_ episode: JellyfinEpisode) -> JellyfinEpisode? {
        guard let index = episodes.firstIndex(where: { $0.id == episode.id }),
              index + 1 < episodes.count else { return nil }
        return episodes[index + 1]
    }

    /// Previous episode in the currently listed season order, if any — the
    /// transport's ⏮ control jumps straight to it.
    private func previousEpisodeBefore(_ episode: JellyfinEpisode) -> JellyfinEpisode? {
        guard let index = episodes.firstIndex(where: { $0.id == episode.id }),
              index > 0 else { return nil }
        return episodes[index - 1]
    }

    /// Series name shown under the episode title in the player's controls;
    /// movies and trailers have no second line.
    private var playerSubtitle: String? {
        playingMediaType == "Episode" ? item.name : nil
    }

    /// Credits overlay → start the next episode IN PLACE. The cover stays
    /// presented, so `PlayerView.onChange(of: streamURL)` swaps the stream and
    /// the user never lands back on the episode list.
    private func playNextEpisode(_ episode: JellyfinEpisode) async {
        await playEpisode(episode)
    }

    // MARK: - User flags

    private func toggleFavorite() {
        guard !isSavingFavorite else { return }
        let desired = !isFavorite
        isFavorite = desired
        userActionError = nil
        isSavingFavorite = true
        Task {
            defer { isSavingFavorite = false }
            do {
                try await JellyfinUserActionClient().setFavorite(
                    desired,
                    userId: userId,
                    serverURL: serverURL,
                    token: token,
                    itemId: item.id
                )
            } catch {
                isFavorite = !desired
                userActionError = "No se pudo actualizar el favorito (\(Self.describe(error)))."
            }
        }
    }

    private func togglePlayed() {
        guard !isSavingPlayed else { return }
        let desired = !isPlayed
        isPlayed = desired
        userActionError = nil
        isSavingPlayed = true
        Task {
            defer { isSavingPlayed = false }
            do {
                try await JellyfinUserActionClient().setPlayed(
                    desired,
                    userId: userId,
                    serverURL: serverURL,
                    token: token,
                    itemId: item.id
                )
            } catch {
                isPlayed = !desired
                userActionError = "No se pudo actualizar el estado de reproducción (\(Self.describe(error)))."
            }
        }
    }

    /// Short reason for the inline banner: a bare "server error 404" is exactly
    /// what tells us the route drifted again.
    private static func describe(_ error: Error) -> String {
        if let libraryError = error as? LibraryError {
            switch libraryError {
            case .unauthorized: return "sesión no válida"
            case .serverError(let code): return "HTTP \(code)"
            default: return libraryError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    // MARK: - Load

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        await fetchDetail(reloadSeasons: true)
    }

    /// (Re)read the item from the server.
    ///
    /// The content stays on screen while the request is in flight — a refresh
    /// must never blank the page it is refreshing.
    ///
    /// - Parameter reloadSeasons: false when the caller already reloads the
    ///   seasons and episodes in parallel.
    private func fetchDetail(reloadSeasons: Bool) async {
        do {
            // PlaybackInfo only feeds the "Vídeo" chips here — a failure must
            // not stop the detail screen from rendering.
            async let playbackInfo = JellyfinPlaybackClient().fetchPlaybackInfo(
                userId: userId,
                serverURL: serverURL,
                token: token,
                itemId: item.id
            )

            let client = JellyfinItemDetailClient()
            let loaded = try await client.fetchItemDetail(
                userId: userId,
                serverURL: serverURL,
                token: token,
                itemId: item.id
            )
            detail = loaded
            isFavorite = loaded.isFavorite
            isPlayed = loaded.isPlayed

            // Load seasons if this is a series
            if loaded.type == "Series", reloadSeasons {
                await loadSeasons()
            }

            if let info = try? await playbackInfo,
               let source = info.mediaSources.first {
                videoChips = VideoInfoChips.chips(from: source)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSeasons() async {
        let libraryClient = JellyfinLibraryClient()
        do {
            async let seasonsRequest = libraryClient.fetchSeasons(
                userId: userId,
                serverURL: serverURL,
                token: token,
                seriesId: item.id
            )
            // The in-progress episode may live in a later season: without this
            // the hero's "Continuar" would only ever find progress in season 1.
            async let resumeRequest = libraryClient.fetchResumeItems(
                userId: userId,
                serverURL: serverURL,
                token: token,
                limit: 50
            )

            seasons = try await seasonsRequest
            guard !seasons.isEmpty else { return }

            if !didChooseInitialSeason {
                let resumeSeason = (try? await resumeRequest)?
                    .first(where: { $0.type == "Episode" && $0.seriesName == item.name })?
                    .parentIndexNumber
                if let resumeSeason,
                   let match = seasons.firstIndex(where: { $0.indexNumber == resumeSeason }) {
                    selectedSeasonIndex = match
                }
                didChooseInitialSeason = true
            }

            // Keep the season the user is looking at — a refresh must not
            // throw them back to the first one.
            let index = min(max(selectedSeasonIndex, 0), seasons.count - 1)
            selectedSeasonIndex = index
            await loadEpisodes(for: seasons[index])
        } catch {
            // Seasons failing shouldn't block the detail page
        }
    }

    /// Load the episodes of a season.
    ///
    /// - Parameter silently: a refresh keeps the current list on screen (and
    ///   keeps it if the request fails). Only the FIRST load shows a spinner
    ///   and may replace the list with an empty one.
    private func loadEpisodes(for season: JellyfinSeason, silently: Bool = false) async {
        let isFirstLoad = episodes.isEmpty
        if !silently || isFirstLoad {
            isLoadingEpisodes = true
        }
        defer { isLoadingEpisodes = false }

        let libraryClient = JellyfinLibraryClient()
        do {
            episodes = try await libraryClient.fetchEpisodes(
                userId: userId,
                serverURL: serverURL,
                token: token,
                seriesId: item.id,
                seasonId: season.id
            )
            episodesError = nil
        } catch {
            // A failed request must NOT wipe the list the user is reading:
            // keep it and say what happened.
            if episodes.isEmpty {
                episodesError = error.localizedDescription
            } else {
                episodesError = "No se pudo actualizar la lista de episodios."
            }
        }
    }

    /// Re-read the season that is on screen after a playback session: the
    /// server owns the progress, so the rows are re-read instead of guessed.
    private func reloadEpisodesAfterPlayback() async {
        guard seasons.indices.contains(selectedSeasonIndex) else { return }
        // The player reports the final position and the "played" flag to
        // Jellyfin asynchronously. Reading the episodes before that report
        // lands would show the PREVIOUS state — wait for it.
        try? await Task.sleep(for: .seconds(1.5))
        await loadEpisodes(for: seasons[selectedSeasonIndex], silently: true)
    }

    // MARK: - Metrics

    /// The navigation bar floats over the top of the hero, so it has to be tall
    /// enough to still show artwork below the pill. 58% of the screen height
    /// (min 460pt, max 620pt) or 520pt on macOS/visionOS makes the hero tall and immersive.
    private var heroHeight: CGFloat {
        #if os(macOS) || os(visionOS)
        520
        #else
        min(max(screenHeight * 0.58, 460), 620)
        #endif
    }

    private var screenHeight: CGFloat {
        #if os(iOS) || os(tvOS)
        UIScreen.main.bounds.height
        #else
        480
        #endif
    }

    /// Desktop windows get very wide: prose at full width is unreadable and
    /// episode rows stretch to absurd sizes. Cap the content column while
    /// letting the hero bleed edge-to-edge.
    private var contentMaxWidth: CGFloat {
        #if os(macOS)
        1100
        #else
        .infinity
        #endif
    }

    private static func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        guard hours > 0 else { return "\(rest) min" }
        return rest > 0 ? "\(hours)h \(rest) min" : "\(hours)h"
    }
}

// MARK: - Action Pill Background

/// iOS 26 already renders its own glass shape around toolbar items — adding a
/// `.regularMaterial` capsule on top of it was the "double glass" look.
private struct ActionPillBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
        #else
        content.background(.regularMaterial, in: Capsule())
        #endif
    }
}

private extension View {
    func actionPillBackground() -> some View {
        modifier(ActionPillBackground())
    }
}

// MARK: - Flow Layout

/// Wraps subviews onto as many lines as needed — technical chips have wildly
/// different widths and a fixed grid looks wrong.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : max(x - spacing, 0), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Episode Row

private struct EpisodeRow: View {
    let episode: JellyfinEpisode
    let serverURL: URL
    let onPlay: () -> Void

    /// The episode's playback state, straight from the server: "watched"
    /// only when Jellyfin says so, "in progress" when there is a position.
    private var watchState: EpisodeWatchState { episode.watchState }

    private var isWatched: Bool { watchState == .watched }

    /// Minutes already watched, when the episode has been started.
    private var watchedMinutes: Int? {
        guard let seconds = episode.resumePositionSeconds, seconds > 0 else { return nil }
        return max(1, Int((seconds / 60).rounded()))
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: 14) {
                thumbnail

                VStack(alignment: .leading, spacing: 5) {
                    Text(episode.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(isWatched ? Color.secondary : Color.primary)

                    if let status {
                        Text(status)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if case .inProgress(let fraction) = watchState, let fraction {
                        ProgressBarView(fraction: fraction)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Image(systemName: isWatched ? "checkmark.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isWatched ? MareaTheme.Colors.accent : MareaTheme.Colors.accent)
                    .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: MareaTheme.Radius.card)
                    .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Reproducir")
    }

    // MARK: - Thumbnail

    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            if let thumbURL = JellyfinArtwork.url(
                for: episode,
                serverURL: serverURL,
                shape: .landscape,
                targetWidth: 160
            ) {
                MareaImageView(url: thumbURL, width: thumbWidth, height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(MareaTheme.Colors.surfaceElevated)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
            }

            // Watched mark. The icon AND the title treatment carry the state:
            // neither depends on the colour alone.
            if isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(MareaTheme.Colors.accent)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityHidden(true)
    }

    private var thumbWidth: CGFloat {
        #if os(macOS)
        176
        #else
        136
        #endif
    }

    private var thumbHeight: CGFloat { thumbWidth * 9 / 16 }

    // MARK: - Text

    /// "42 min", "42 min · Vas por 18 min" or "42 min · Visto".
    private var status: String? {
        var parts: [String] = []
        if let duration = episode.durationMinutes {
            parts.append("\(duration) min")
        }
        switch watchState {
        case .unwatched:
            break
        case .inProgress:
            if let minutes = watchedMinutes {
                parts.append("Vas por \(minutes) min")
            }
        case .watched:
            parts.append("Visto")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The state in words, so VoiceOver never has to guess from a colour.
    /// The full title is part of the label: "T1 E3" alone does not tell the
    /// user which chapter they are on.
    private var accessibilityLabel: String {
        let name = episode.displayTitle
        switch watchState {
        case .unwatched:
            return "\(name). No visto."
        case .inProgress(let fraction):
            guard let fraction else {
                let minutes = watchedMinutes.map { "Vas por \($0) minutos" } ?? "En curso"
                return "\(name). En progreso. \(minutes)."
            }
            let percent = Int((fraction * 100).rounded())
            return "\(name). En progreso, \(percent) por ciento."
        case .watched:
            return "\(name). Visto."
        }
    }
}
