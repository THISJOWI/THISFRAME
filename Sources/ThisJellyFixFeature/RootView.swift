import Observation
import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking
#if os(macOS)
import AppKit
#endif
#if canImport(CoreSpotlight)
import CoreSpotlight
#endif
#if os(iOS)
import AVFoundation
#endif

public struct ThisFrameRootView: View {
    @State private var model = ServerConnectionModel()
    @State private var authModel = AuthModel()
    @State private var libraryModel: LibraryModel?
    @State private var isLoadingLibrary = false
    /// Discovery + downloads state. Rebuilt whenever the library model
    /// changes so its library snapshot points at the live model.
    @State private var discoveryModel: DiscoveryModel?
    #if os(iOS) || os(tvOS)
    @State private var selectedTab: MareaTab = .home
    #endif
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    /// Floating PiP whose fullscreen player was already dismissed: the root
    /// view is the only owner that survives the player, so it re-presents it
    /// when the system asks for the UI back (4.5 — the old restore closure
    /// lived in the player's view model and died with it).
    @State private var restoredPlayback: RestoredPlayback?
    /// Root registrations live for the process lifetime (static, not @State:
    /// SwiftUI may rebuild the view, re-registering must not stack handlers).
    private static var pipRestoreHandlerId: UUID?
    private static var pipClosedHandlerId: UUID?

    /// Everything needed to rebuild the fullscreen player at `position`.
    private struct RestoredPlayback: Identifiable {
        let id = UUID()
        let context: PipContext
        let position: Double
        /// The floating VM itself — same AVPlayer, no re-prepare.
        let viewModel: PlayerViewModel
    }
    #endif

    public init() {}

    /// Decoded Handoff payload waiting to be acted on until the library is
    /// actually loaded (kept, never consumed early — see `HandoffResolver`).
    @State private var pendingHandoff: HandoffIntent?

    /// Appearance preference (Core). "system" leaves the color scheme to the
    /// OS — the app must not force a scheme in that mode.
    @AppStorage(AppearanceSettings.Key.appearance)
    private var appearanceRaw: String = AppearanceSettings.Appearance.system.rawValue

    /// The scheme the app forces, or `nil` to follow the system.
    private var preferredColorScheme: ColorScheme? {
        switch AppearanceSettings.Appearance(rawValue: appearanceRaw) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    #if os(macOS)
    /// macOS resolves dynamic colors against `NSAppearance`, NOT against
    /// SwiftUI's color scheme — so a forced light/dark mode has to set the
    /// app appearance too, or the theme tokens keep resolving the dark
    /// variant while the text turns black: unreadable pages.
    private func applyMacAppearance() {
        // The test bundle has no NSApp — nothing to style there.
        guard let app = NSApp else { return }
        app.appearance = MacAppearance.appAppearance(
            for: AppearanceSettings.current().appearance
        )
    }
    #endif

    public var body: some View {
        ZStack {
            #if os(iOS)
            // Layer host for the floating PiP session. It must be alive for the
            // WHOLE app lifetime: the coordinator attaches the layer synchronously
            // the moment a session floats, and starting PiP a render early (with
            // `superlayer == nil`) is what made the window never appear. It sits
            // BEHIND the opaque gradient so an active session can never paint
            // over Home (the black box that was covering the rows); `cleanup()`
            // detaches the layer when the session ends.
            PipLayerHostView(isActive: PipCoordinator.shared.isActive)
                .allowsHitTesting(false)
            #endif
            // Pure black — the content (cards, hero, art) provides the color.
            MareaTheme.Colors.background
                .ignoresSafeArea()

            if let server = model.server {
                if authModel.isAuthenticated {
                    if let libModel = libraryModel {
                        // Home renders its own loading skeleton, so the app is
                        // interactive while the row requests are still flying.
                        #if os(iOS)
                        mainContent(libModel: libModel, server: server)
                            .environment(discoveryModel)
                        #elseif os(tvOS)
                        // Native tvOS TabView: top tab bar with system focus
                        // and tvOS styling — Home used to be the only screen.
                        tvOSTabContent(libModel: libModel, server: server)
                            .environment(discoveryModel)
                        #else
                        HomeView(
                            libraryModel: libModel,
                            serverURL: server.baseURL,
                            token: authModel.token ?? "",
                            userId: authModel.currentUser?.id ?? "",
                            userName: authModel.currentUser?.name ?? "",
                            onLogout: {
                                authModel.logout()
                                libraryModel = nil
                            }
                        )
                        .environment(discoveryModel)
                        #endif
                    } else if isLoadingLibrary {
                        ProgressView("Cargando biblioteca…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Color.clear
                            .onAppear {
                                Task { await loadLibrary() }
                            }
                    }
                } else {
                    LoginView(
                        serverName: server.name,
                        serverURL: server.baseURL,
                        authModel: authModel,
                        onBack: { model.disconnect() }
                    )
                }
            } else {
                ServerConnectionView(model: model)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        #if os(iOS)
        // The system asks for the fullscreen UI back when the user taps the
        // floating window and no player is alive to claim the request.
        .fullScreenCover(item: $restoredPlayback) { restored in
            restoredPlayerView(restored)
        }
        .onChange(of: selectedTab) { _, tab in
            // TabView keeps views alive, so onAppear won't re-fire on tab
            // switches — refresh resume when user returns to Inicio.
            if tab == .home, let lib = libraryModel {
                Task { await lib.refreshResume() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from another app/client: Home is still mounted, so
            // NO onAppear fires, and progress recorded elsewhere (web, TV,
            // another phone) never reached "Estás viendo".
            guard phase == .active, let lib = libraryModel else { return }
            Task { await lib.refreshResume() }
        }
        .onAppear {
            configureAudioSession()
            registerPipHandlers()
            LocalNetworkAuthorizer.shared.triggerPrompt()
            #if os(macOS)
            applyMacAppearance()
            #endif
        }
        #if os(macOS)
        .onChange(of: appearanceRaw) { _, _ in
            applyMacAppearance()
        }
        #endif
        #endif
        .task {
            if model.server != nil && !authModel.isAuthenticated {
                _ = await authModel.restoreSession(serverURL: model.server!.baseURL)
            }
        }
        // MARK: - Handoff reception
        // Browsing: just open the app — nothing extra to do.
        .onContinueUserActivity(HandoffActivity.browsing) { _ in
            #if os(iOS)
            selectedTab = .home
            #endif
        }
        // Detail: navigate to the item's detail screen.
        .onContinueUserActivity(HandoffActivity.detail) { activity in
            TJFLog("handoff: received 'detail' keys=\(activity.userInfo.map { Array($0.keys) } ?? [])")
            guard let info       = activity.userInfo,
                  let itemId     = info[HandoffActivity.Key.itemId]     as? String,
                  let serverStr  = info[HandoffActivity.Key.serverURL]  as? String,
                  let serverURL  = URL(string: serverStr)
            else {
                TJFLog("handoff: 'detail' payload DECODE FAILED info=\(String(describing: activity.userInfo))")
                return
            }
            // itemId/serverURL are the hard requirements (they locate the
            // content); title/mediaType are cosmetic — tolerate their absence
            // instead of dropping the whole continuation (M2).
            let title     = info[HandoffActivity.Key.title]     as? String ?? ""
            let mediaType = info[HandoffActivity.Key.mediaType] as? String ?? ""

            pendingHandoff = HandoffIntent(
                itemId: itemId,
                serverURL: serverURL,
                title: title,
                mediaType: mediaType,
                position: nil
            )
            #if os(iOS)
            selectedTab = .home
            #endif
        }
        // Playing: open the detail screen (or the player directly if possible)
        // at the stored position so the user picks up right where they left off.
        .onContinueUserActivity(HandoffActivity.playing) { activity in
            TJFLog("handoff: received 'playing' act=\(activity.activityType ?? "-") keys=\(activity.userInfo.map { Array($0.keys) } ?? [])")
            guard let info       = activity.userInfo,
                  let itemId     = info[HandoffActivity.Key.itemId]     as? String,
                  let serverStr  = info[HandoffActivity.Key.serverURL]  as? String,
                  let serverURL  = URL(string: serverStr)
            else {
                TJFLog("handoff: 'playing' payload DECODE FAILED info=\(String(describing: activity.userInfo))")
                return
            }

            let position  = info[HandoffActivity.Key.position] as? Double
            let title     = info[HandoffActivity.Key.title]     as? String ?? ""
            let mediaType = info[HandoffActivity.Key.mediaType] as? String ?? ""
            TJFLog("handoff: 'playing' itemId=\(itemId) pos=\(String(describing: position)) server=\(serverURL)")

            pendingHandoff = HandoffIntent(
                itemId: itemId,
                serverURL: serverURL,
                title: title,
                mediaType: mediaType,
                position: position
            )
            #if os(iOS)
            selectedTab = .home
            #endif
        }
        #if canImport(CoreSpotlight) && !os(tvOS)
        // Spotlight Search result tapped by the user in system search.
        // CoreSpotlight imports on tvOS, but CSSearchableItemActionType is
        // marked unavailable there — guard it out or the tvOS target won't build.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            let prefix = "tjf://item/"
            let itemId = identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : identifier
            guard let server = model.server else { return }

            pendingHandoff = HandoffIntent(
                itemId: itemId,
                serverURL: server.baseURL,
                title: "",
                mediaType: "",
                position: nil
            )
            #if os(iOS)
            selectedTab = .home
            #endif
        }
        #endif
        // Once a payload arrives AND the library is loaded, find the item and
        // push the DetailView. The library may still be loading when the
        // activity fires, so we watch both triggers.
        .onChange(of: pendingHandoff) { _, newPayload in
            // m6: observe the WHOLE struct — a second continuation for the
            // same itemId (new position) never changes `pendingHandoff?.itemId`
            // and would be silently ignored.
            guard newPayload != nil else { return }
            resolveHandoffIfReady()
        }
        .onChange(of: libraryModel != nil) { _, ready in
            guard ready else { return }
            resolveHandoffIfReady()
        }
        // The library model exists BEFORE its rows load (published so Home can
        // render its skeleton). A pending Handoff must survive until load()
        // completes — this is the trigger the cold-launch path was missing.
        .onChange(of: libraryModel?.hasLoaded ?? false) { _, loaded in
            guard loaded else { return }
            resolveHandoffIfReady()
        }
    }

    #if os(iOS)
    /// Static stream URL (4.3): the app used to let whichever player started
    /// first configure the session implicitly. Category is set once, up front;
    /// activation stays with the players (activating on the login screen would
    /// silence whatever else is playing).
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playback, mode: .moviePlayback)
            TJFLog("audio session: category=.playback configured")
        } catch {
            TJFLog("audio session: configure FAILED \(error)")
        }
    }

    /// Permanent PiP observers: the live player registers while its view is on
    /// screen and unregisters on disappear, so without these the system's
    /// restore request had NO owner once the cover closed → PiP died (4.5).
    private func registerPipHandlers() {
        if let id = Self.pipRestoreHandlerId {
            PipCoordinator.shared.removeRestoreHandler(id)
        }
        if let id = Self.pipClosedHandlerId {
            PipCoordinator.shared.removeClosedHandler(id)
        }

        Self.pipRestoreHandlerId = PipCoordinator.shared.addRestoreHandler { [self] position in
            // Another fullscreen player already owns the UI (Home's direct
            // player, DetailView's cover): presenting a SECOND one on top
            // fails silently — the system had already been told "yes", so the
            // window closed with nothing playing. Refuse instead: the session
            // then reports stop and the resume entry survives.
            guard PlayerView.presentedCount == 0 else {
                TJFLog("pip: root refuses restore — \(PlayerView.presentedCount) fullscreen player(s) on screen")
                return false
            }
            // The coordinator holds the floating VM + context until the
            // restored view adopts them (releaseFloating on appear).
            guard let ctx = PipCoordinator.shared.floatingContext,
                  let vm = PipCoordinator.shared.floatingVM
            else {
                TJFLog("pip: root cannot restore — floating session gone")
                return false
            }
            TJFLog("pip: root re-presenting fullscreen player at \(String(format: "%.1f", position))s")
            restoredPlayback = RestoredPlayback(context: ctx, position: position, viewModel: vm)
            return true
        }
        Self.pipClosedHandlerId = PipCoordinator.shared.addClosedHandler { [self] in
            // Floating window closed while root owned the player: the session
            // reported the stop, so the row must reflect it right now.
            restoredPlayback = nil
            refreshResumeSoon()
        }
    }

    /// Rebuild the fullscreen player from a floating PiP session. Kept out of
    /// `body`'s closure: the root's view expression already sits at the
    /// type-checker's per-expression budget, and the full parameter list tips
    /// it over. Passes the restored context through so the rebuilt player
    /// keeps the same audio mapping, subtitle line and media type.
    private func restoredPlayerView(_ restored: RestoredPlayback) -> PlayerView {
        PlayerView(
            streamURL: restored.context.streamURL,
            title: restored.context.title,
            startPosition: restored.position,
            onDismiss: {
                restoredPlayback = nil
                refreshResumeSoon()
            },
            itemId: restored.context.itemId,
            serverURL: restored.context.serverURL,
            token: restored.context.token,
            userId: restored.context.userId,
            mediaType: restored.context.mediaType,
            playSessionId: restored.context.playSessionId,
            mediaStreams: restored.context.mediaStreams,
            audioServerIndex: restored.context.audioServerIndex,
            subtitle: restored.context.subtitle,
            restoredViewModel: restored.viewModel
        )
    }

    /// Forced resume-row refresh AFTER the stop POST has had time to land.
    /// Refreshing immediately (or relying on the 5s cooldown) let the row be
    /// fetched in its pre-stop state and then blocked the correction — the
    /// user then saw the episode as "progress lost".
    private func refreshResumeSoon() {
        guard let lib = libraryModel else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await lib.refreshResume(force: true)
        }
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private func mainContent(libModel: LibraryModel, server: JellyfinServer) -> some View {
        let token = authModel.token ?? ""
        let userId = authModel.currentUser?.id ?? ""
        let userName = authModel.currentUser?.name ?? ""

        if #available(iOS 26, *) {
            // Native TabView with Tab items — iOS 26 Liquid Glass already
            // renders the floating pill + minimizes on scroll, so the custom
            // bar would only regress system behavior here.
            TabView(selection: $selectedTab) {
                Tab("Inicio", systemImage: "house.fill", value: MareaTab.home) {
                    HomeView(
                        libraryModel: libModel,
                        serverURL: server.baseURL,
                        token: token,
                        userId: userId,
                        userName: userName,
                        onLogout: { authModel.logout(); libraryModel = nil }
                    )
                }

                Tab("Buscar", systemImage: "magnifyingglass", value: MareaTab.search) {
                    SearchView(serverURL: server.baseURL, token: token, userId: userId)
                }

                Tab("Perfil", systemImage: "person.fill", value: MareaTab.profile) {
                    ProfileView(
                        userName: userName,
                        onLogout: { authModel.logout(); libraryModel = nil },
                        serverURL: server.baseURL,
                        token: token,
                        userId: userId
                    )
                }
            }
            .tint(MareaTheme.Colors.accent)
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            // iOS 17–25: hide the native bar and float our glass pill instead
            // (Netflix-style). Tab selection and swipe still work — only the
            // system bar chrome is suppressed.
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    HomeView(
                        libraryModel: libModel,
                        serverURL: server.baseURL,
                        token: token,
                        userId: userId,
                        userName: userName,
                        onLogout: { authModel.logout(); libraryModel = nil }
                    )
                    .toolbar(.hidden, for: .tabBar)
                    .tag(MareaTab.home)

                    SearchView(serverURL: server.baseURL, token: token, userId: userId)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(MareaTab.search)

                    ProfileView(
                        userName: userName,
                        onLogout: { authModel.logout(); libraryModel = nil },
                        serverURL: server.baseURL,
                        token: token,
                        userId: userId
                    )
                    .toolbar(.hidden, for: .tabBar)
                    .tag(MareaTab.profile)
                }
                .tint(MareaTheme.Colors.accent)

                FloatingTabBar(selection: $selectedTab)
                    .padding(.bottom, MareaTheme.Spacing.sm)
            }
        }
    }
    #endif

    #if os(tvOS)
    /// tvOS tabs: the system TabView renders the top bar with native focus
    /// engine support and tvOS styling — no custom pill (tvOS convention is
    /// the top tab bar, as in the TV app / Netflix).
    @ViewBuilder
    private func tvOSTabContent(libModel: LibraryModel, server: JellyfinServer) -> some View {
        let token = authModel.token ?? ""
        let userId = authModel.currentUser?.id ?? ""
        let userName = authModel.currentUser?.name ?? ""

        TabView(selection: $selectedTab) {
            HomeView(
                libraryModel: libModel,
                serverURL: server.baseURL,
                token: token,
                userId: userId,
                userName: userName,
                onLogout: { authModel.logout(); libraryModel = nil }
            )
            .tabItem { Label("Inicio", systemImage: "house.fill") }
            .tag(MareaTab.home)

            SearchView(serverURL: server.baseURL, token: token, userId: userId)
                .tabItem { Label("Buscar", systemImage: "magnifyingglass") }
                .tag(MareaTab.search)

            ProfileView(
                userName: userName,
                onLogout: { authModel.logout(); libraryModel = nil },
                serverURL: server.baseURL,
                token: token,
                userId: userId
            )
            .tabItem { Label("Perfil", systemImage: "person.fill") }
            .tag(MareaTab.profile)
        }
        .tint(MareaTheme.Colors.accent)
    }
    #endif

    private func loadLibrary() async {
        guard !isLoadingLibrary else { return }
        guard let server = model.server,
              let user = authModel.currentUser else { return }

        guard let token = authModel.token else { return }

        isLoadingLibrary = true
        defer { isLoadingLibrary = false }

        let libModel = LibraryModel(
            serverURL: server.baseURL,
            userId: user.id,
            token: token
        )
        // Publish BEFORE loading: the view tree switches straight to Home (which
        // shows its own skeleton) instead of holding the whole screen hostage
        // until every row request finishes.
        libraryModel = libModel
        // Discovery reads the live library through the same reference, so its
        // TMDB matching sees rows as they land.
        discoveryModel = DiscoveryModel.live { [weak libModel] in
            libModel?.allItems ?? []
        }
        await libModel.load()
        // Rows landed: discovery can now seed recommendations from them.
        await discoveryModel?.loadRows()
    }

    // MARK: - Handoff resolution

    /// Called whenever a pending Handoff payload arrives OR the library finishes
    /// loading — whichever comes last.  Finds the item by ID in the already-loaded
    /// rows and pushes a navigation destination (iOS: NavigationLink value via
    /// a dedicated @State property; all platforms share the same logic path).
    private func resolveHandoffIfReady() {
        guard let payload = pendingHandoff,
              let lib = libraryModel else {
            TJFLog("handoff: resolve deferred payload=\(pendingHandoff != nil) library=\(libraryModel != nil)")
            return
        }

        // Find the item in the already-loaded library rows.
        let match = lib.allItems.first { $0.id == payload.itemId }
        let state: HandoffLibraryState = lib.hasLoaded
            ? .loaded(itemCount: lib.allItems.count)
            : .notLoaded

        switch HandoffResolver.resolve(intent: payload, library: state, itemExists: match != nil) {
        case .idle:
            return
        case .keepWaiting(let reason):
            // NOT consumed: the payload stays pending until load() finishes.
            // The old code cleared it here, so a cold launch resolved against
            // an empty library and navigated nowhere ("Dock → app → nothing").
            TJFLog("handoff: resolve deferred (\(reason)) item=\(payload.itemId)")
            return
        case .expired:
            TJFLog("handoff: intent EXPIRED item=\(payload.itemId) (unresolvable within \(Int(HandoffResolver.intentLifetime)) s) — dropped")
            pendingHandoff = nil
            return
        case .notFound:
            TJFLog("handoff: item \(payload.itemId) NOT in library (\(lib.allItems.count) items, loaded=\(lib.hasLoaded)) — no navigation")
            pendingHandoff = nil
            return
        case .navigate:
            guard let item = match else { return }
            TJFLog("handoff: → pendingNavigationItem \(item.name) pos=\(String(describing: payload.position))")
            // Handoff position rides along so DetailView can start playback
            // exactly where the other device was (max with server resume).
            lib.pendingNavigationPosition = payload.position
            lib.pendingNavigationItem = item
            pendingHandoff = nil
        }
    }
}

// MARK: - Server Connection

@MainActor
@Observable
final class ServerConnectionModel {
    var address = ""
    var isConnecting = false
    var errorMessage: String?
    var server: JellyfinServer?
    /// Lista persistente de dominios (fuente de verdad del selector).
    var savedServers: [JellyfinServer] = []

    private let probe: any JellyfinServerProbing
    private let keychain: any KeychainStoring

    init(
        probe: any JellyfinServerProbing = JellyfinServerProbe(),
        keychain: any KeychainStoring = KeychainStore()
    ) {
        self.probe = probe
        self.keychain = keychain
        // 1. Cargar lista; 2. migrar clave histórica si la lista está vacía;
        // 3. restaurar selección actual (re-normalizando para evitar
        // trailing-slash / scheme inconsistentes).
        var loaded = SavedServersStore.load(from: keychain)
        let migrated = SavedServersStore.migrateLegacyIfNeeded(current: loaded, keychain: keychain)
        if loaded.isEmpty && !migrated.isEmpty {
            loaded = migrated
            do {
                try SavedServersStore.save(loaded, to: keychain)
            } catch {
                TJFLog("servers: migración legacy falló — \(error.localizedDescription)")
            }
        }
        savedServers = loaded
        if let urlString = keychain.read(key: KeychainKey.serverURL) {
            let url: URL? = (try? ServerAddress.normalizedURL(from: urlString)) ?? URL(string: urlString)
            if let url {
                let key = SavedServersStore.dedupeKey(for: url)
                if let match = loaded.first(where: { SavedServersStore.dedupeKey(for: $0.baseURL) == key }) {
                    server = match
                } else {
                    server = JellyfinServer(baseURL: url, name: url.host ?? "Server")
                }
            }
        } else if loaded.count == 1 {
            // Sin "actual" marcado pero con un único guardado: no auto-seleccionar.
            // El usuario elige explícitamente (evita fantasma tras disconnect).
            server = nil
        }
    }

    func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let url = try ServerAddress.normalizedURL(from: address)
            let info = try await probe.publicInfo(at: url)
            let newServer = JellyfinServer(baseURL: url, name: info.serverName.isEmpty ? (url.host ?? "Server") : info.serverName)
            // Upsert + persistencia inmediata (antes solo memoria: se perdía al cerrar).
            savedServers = SavedServersStore.upsert(savedServers, server: newServer)
            do {
                try SavedServersStore.save(savedServers, to: keychain)
                try keychain.save(key: KeychainKey.serverURL, value: url.absoluteString)
            } catch {
                TJFLog("servers: persistencia falló — \(error.localizedDescription)")
                errorMessage = "No se pudo guardar el servidor: \(error.localizedDescription)"
                return
            }
            // Resolver identidad estable (conserva id existente si era duplicado).
            let key = SavedServersStore.dedupeKey(for: url)
            server = savedServers.first(where: { SavedServersStore.dedupeKey(for: $0.baseURL) == key }) ?? newServer
            address = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Selecciona un servidor guardado sin re-probar (ya validado al añadir).
    func select(_ saved: JellyfinServer) {
        server = saved
        address = ""
        errorMessage = nil
        do {
            try keychain.save(key: KeychainKey.serverURL, value: saved.baseURL.absoluteString)
        } catch {
            TJFLog("servers: no se pudo marcar actual — \(error.localizedDescription)")
            errorMessage = "No se pudo seleccionar el servidor: \(error.localizedDescription)"
        }
    }

    func removeSavedServer(id: JellyfinServer.ID) {
        savedServers.removeAll { $0.id == id }
        do {
            try SavedServersStore.save(savedServers, to: keychain)
            if let current = server, current.id == id {
                server = nil
                try? keychain.delete(key: KeychainKey.serverURL)
            }
            // Si la lista queda vacía, limpiar también la clave actual.
            if savedServers.isEmpty {
                try? keychain.delete(key: KeychainKey.serverURL)
            }
        } catch {
            TJFLog("servers: no se pudo eliminar — \(error.localizedDescription)")
            errorMessage = "No se pudo eliminar el servidor: \(error.localizedDescription)"
        }
        // Recargar para no dejar estado divergente si el save falló a medias.
        savedServers = SavedServersStore.load(from: keychain)
        if let current = server,
           !savedServers.contains(where: { $0.id == current.id }) {
            // El actual ya no está en la lista persistida: mantenerlo en memoria
            // solo si el borrado falló; si se eliminó de verdad, ya es nil arriba.
            _ = current
        }
    }

    func disconnect() {
        // Solo limpia la selección en memoria + la marca de "actual".
        // La LISTA guardada se conserva (no es un "olvidar todo").
        server = nil
        address = ""
        errorMessage = nil
        do {
            try keychain.delete(key: KeychainKey.serverURL)
        } catch {
            TJFLog("servers: disconnect no pudo limpiar actual — \(error.localizedDescription)")
        }
    }
}

// MARK: - Server Connection View

private struct ServerConnectionView: View {
    @Bindable var model: ServerConnectionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("AppIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: MareaTheme.Colors.accent.opacity(0.3), radius: 12)

                VStack(spacing: 8) {
                    Text("THISJELLYFIX")
                        .font(.largeTitle.bold())
                    Text("Tu biblioteca. A tu manera.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Servidor Jellyfin")
                        .font(.headline)
                    TextField("https://jellyfin.example.com", text: $model.address)
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        #endif
                        .disableAutocorrection(true)
                        .padding(12)
                        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))
                        .submitLabel(.go)
                        .onSubmit { Task { await model.connect() } }

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: 440)

                Button {
                    Task { await model.connect() }
                } label: {
                    if model.isConnecting {
                        ProgressView().tint(.black)
                    } else {
                        Text(model.savedServers.isEmpty ? "Conectar" : "Añadir servidor")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MareaTheme.Colors.accent)
                .disabled(model.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isConnecting)

                if !model.savedServers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Servidores guardados")
                            .font(.headline)
                        ForEach(model.savedServers) { saved in
                            HStack(spacing: 12) {
                                Button {
                                    model.select(saved)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(saved.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(saved.baseURL.absoluteString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    model.removeSavedServer(id: saved.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Eliminar \(saved.name)")
                            }
                            .padding(12)
                            .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .frame(maxWidth: 440)
                }
            }
            .padding(32)
        }
    }
}
