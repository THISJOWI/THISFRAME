import SwiftUI
import ThisJellyFixCore

struct HomeView: View {
    let libraryModel: LibraryModel
    let serverURL: URL
    let token: String
    let userId: String
    let userName: String
    let onLogout: () -> Void

    /// Episode or movie tapped on a card — played directly, without pushing DetailView.
    @State private var directItem: JellyfinMediaItem?
    /// nil = discovery not configured (or tvOS/visionOS) → rows never render.
    @Environment(DiscoveryModel.self) private var discovery: DiscoveryModel?
    /// Programmatic navigation path: Handoff resolution injects an item here so
    /// the NavigationStack pushes the DetailView immediately.
    @State private var navigationPath = NavigationPath()

    var body: some View {
        #if os(macOS)
        sidebarLayout
        #else
        NavigationStack(path: $navigationPath) {
            scrollContent
                .navigationDestination(for: JellyfinMediaItem.self) { item in
                    detailDestination(for: item)
                }
                #if os(iOS) || os(macOS)
                .navigationDestination(for: CatalogItem.self) { item in
                    CatalogDetailView(item: item)
                }
                .navigationDestination(for: CategoryChip.self) { chip in
                    LibraryGridView(
                        title: chip.title,
                        parentId: chip.parentId,
                        includeTypes: chip.includeTypes,
                        serverURL: serverURL,
                        token: token,
                        userId: userId
                    )
                }
                #endif
        }
        // Publish a Handoff activity so the user can continue browsing on
        // another Apple device. YIELDS while playback owns Handoff (two
        // eligible activities competing is how the Mac Dock advertised
        // "browsing" instead of "playing") AND while any detail screen is on
        // top — DetailView claims the slot via onAppear (counted in
        // HandoffCenter, so taps, handoff pushes and nested stacks all work).
        // Catalog pushes keep browsing: CatalogDetailView publishes nothing.
        .userActivity(
            HandoffActivity.browsing,
            isActive: HandoffCenter.shared.shouldPublishBrowsing
        ) { activity in
            activity.title = "Explorando la biblioteca"
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch  = false
        }
        // m7: the destination builder READS pendingNavigationPosition without
        // clearing (side effects there raced SwiftUI's re-evaluations). The
        // value normally dies at DetailView read time (onHandoffConsumed);
        // this is the belt-and-braces clear when the stack empties.
        .onChange(of: navigationPath) { _, path in
            if path.isEmpty { libraryModel.pendingNavigationPosition = nil }
        }
        // React to a Handoff-resolved item coming from LibraryModel.
        .onChange(of: libraryModel.pendingNavigationItem) { _, item in
            guard let item else { return }
            navigationPath.append(item)
            libraryModel.pendingNavigationItem = nil
        }
        // C3: if the intent landed BEFORE this stack subscribed (cold launch),
        // onChange never fires for a value already set — consume it here too.
        .onAppear {
            guard let item = libraryModel.pendingNavigationItem else { return }
            TJFLog("handoff: ios consumed pre-subscription item \(item.name)")
            navigationPath.append(item)
            libraryModel.pendingNavigationItem = nil
        }
        #endif
    }

    /// Shared DetailView factory: hands over the Handoff position.
    /// m7: READ-only — the builder runs on every SwiftUI re-evaluation, so
    /// clearing here could instantiate DetailView with nil on a second pass
    /// and kill the autoplay. Cleared on stack pop instead.
    private func detailDestination(for item: JellyfinMediaItem) -> DetailView {
        return DetailView(
            item: item, serverURL: serverURL, token: token, userId: userId,
            onPlayerDismiss: { Task {
                // Wait for the async reportStopped HTTP request to land
                // before re-fetching, otherwise the server has no progress yet.
                // Only the resume row changes after playback, so refresh
                // just that row instead of re-running the whole library load.
                try? await Task.sleep(for: .seconds(2))
                await libraryModel.refreshResume(force: true)
            } },
            handoffPosition: libraryModel.pendingNavigationPosition,
            onHandoffConsumed: { libraryModel.pendingNavigationPosition = nil }
        )
    }

    // MARK: - macOS Sidebar

    #if os(macOS)
    @State private var selectedTab: MareaTab = .home

    private var sidebarLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Logo header
                HStack {
                    Image("AppIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Inicio")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                List {
                    Section("Navegación") {
                        ForEach(MareaTab.allCases.filter { $0 != .favorites }, id: \.self) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Label(tab.label, systemImage: tab.icon)
                                    .foregroundStyle(selectedTab == tab ? MareaTheme.Colors.accent : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(minWidth: 200)
        } detail: {
            macTabContent(selectedTab)
                .id(selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
        // React to a Handoff-resolved item: push it into the mac home stack.
        // (The iOS branch has its own copy inside NavigationStack; mac had NONE
        // — accepting a Handoff on the Mac navigated nowhere.)
        .onChange(of: libraryModel.pendingNavigationItem) { _, item in
            guard let item else { return }
            // Only the home detail stack is bound to navigationPath.
            selectedTab = .home
            navigationPath.append(item)
            libraryModel.pendingNavigationItem = nil
            TJFLog("handoff: mac pushed \(item.name) onto navigationPath")
        }
        // C3: cold launch can set the intent before the consumer subscribes —
        // an already-set value never triggers onChange. Consume on appear too.
        .onAppear {
            guard let item = libraryModel.pendingNavigationItem else { return }
            TJFLog("handoff: mac consumed pre-subscription item \(item.name)")
            selectedTab = .home
            navigationPath.append(item)
            libraryModel.pendingNavigationItem = nil
        }
    }

    @ViewBuilder
    private func macTabContent(_ tab: MareaTab) -> some View {
        switch tab {
        case .home:
            // Programmatic path so the mac handoff can push DetailView too —
            // the consumer lives on sidebarLayout (mac used to drop
            // pendingNavigationItem on the floor: nothing navigated).
            NavigationStack(path: $navigationPath) {
                scrollContent
                    .navigationDestination(for: JellyfinMediaItem.self) { item in
                        detailDestination(for: item)
                    }
                    #if os(iOS) || os(macOS)
                    .navigationDestination(for: CatalogItem.self) { item in
                        CatalogDetailView(item: item)
                    }
                    .navigationDestination(for: CategoryChip.self) { chip in
                        LibraryGridView(
                            title: chip.title,
                            parentId: chip.parentId,
                            includeTypes: chip.includeTypes,
                            serverURL: serverURL,
                            token: token,
                            userId: userId
                        )
                    }
                    #endif
            }
            // m7 (mac mirror): belt-and-braces clear when the stack empties —
            // DetailView normally consumes the position at read time.
            .onChange(of: navigationPath) { _, path in
                if path.isEmpty { libraryModel.pendingNavigationPosition = nil }
            }
        case .search:
            SearchView(serverURL: serverURL, token: token, userId: userId)
        case .favorites:
            // Favorites removed from sidebar — redirect to home
            NavigationStack {
                scrollContent
                    .navigationDestination(for: JellyfinMediaItem.self) { item in
                        DetailView(
                            item: item, serverURL: serverURL, token: token, userId: userId,
                            onPlayerDismiss: { Task {
                            // Wait for the async reportStopped HTTP request to land
                            // before re-fetching, otherwise the server has no progress yet.
                            // Only the resume row changes after playback, so refresh
                            // just that row instead of re-running the whole library load.
                            try? await Task.sleep(for: .seconds(2))
                            await libraryModel.refreshResume(force: true)
                        } }
                        )
                    }
            }
        case .profile:
            ProfileView(userName: userName, onLogout: onLogout, serverURL: serverURL, token: token, userId: userId)
        }
    }
    #endif

    // MARK: - Scroll Content (shared)

    #if os(iOS) || os(macOS)
    /// Trending shelves — nil discovery (tvOS/visionOS or no config) = empty.
    @ViewBuilder
    private var trendingShelf: some View {
        if let discovery {
            ForEach(discovery.trendingRows) { row in
                DiscoveryRowView(row: row, discovery: discovery)
            }
        }
    }

    /// Homogeneous "para ti" shelves (series/movies/anime kept apart).
    @ViewBuilder
    private var forYouShelf: some View {
        if let discovery {
            ForEach(discovery.forYouRows) { row in
                DiscoveryRowView(row: row, discovery: discovery)
            }
        }
    }
    #endif

    private var scrollContent: some View {
        // Resume ids feed the card badges ("Siguiente episodio") on every row.
        let resumeIds = Set(
            libraryModel.rows.first(where: { $0.title == "Estás viendo" })?.items.map(\.id) ?? []
        )
        let base = ScrollView {
            VStack(alignment: .leading, spacing: MareaTheme.Spacing.lg) {
                HStack {
                    Image("AppIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Inicio")
                        .font(.largeTitle.bold())
                    Spacer()

                    #if os(iOS) || os(macOS)
                    if let discovery, discovery.hasDownloadService {
                        DownloadsButton(discovery: discovery)
                    }
                    #endif
                }
                .padding(.horizontal, MareaTheme.Spacing.xl)

                // E4: dead token — the retry button can never succeed, so the
                // banner (and the empty-state button) offer a real way out.
                if libraryModel.sessionExpired {
                    HStack(spacing: 12) {
                        Label("Sesión expirada", systemImage: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Cerrar sesión", action: onLogout)
                            .buttonStyle(.bordered)
                            .tint(MareaTheme.Colors.accent)
                    }
                    .padding(.horizontal, MareaTheme.Spacing.xl)
                }

                if libraryModel.isLoading && libraryModel.rows.isEmpty {
                    // Shimmering placeholders shaped like the real content —
                    // the layout is already there when the rows land.
                    VStack(alignment: .leading, spacing: MareaTheme.Spacing.lg) {
                        SkeletonRowView()
                        SkeletonRowView()
                        SkeletonRowView()
                    }
                    .padding(.top, MareaTheme.Spacing.lg)
                } else if let error = libraryModel.errorMessage, libraryModel.rows.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                        if libraryModel.sessionExpired {
                            Button("Cerrar sesión", action: onLogout)
                                .buttonStyle(.borderedProminent)
                                .tint(MareaTheme.Colors.accent)
                        } else {
                            Button("Reintentar") { Task { await libraryModel.load() } }
                                .buttonStyle(.borderedProminent)
                                .tint(MareaTheme.Colors.accent)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    #if os(iOS) || os(macOS)
                    categoryChips
                    if libraryModel.rows.isEmpty {
                        trendingShelf
                    }
                    #endif

                    heroCarousel()

                    ForEach(Array(libraryModel.rows.enumerated()), id: \.element.id) { index, row in
                        RowSection(
                            title: row.title,
                            items: row.items,
                            wide: row.title == "Estás viendo",
                            badgeFor: {
                                CardBadge.badge(
                                    for: $0,
                                    resumeItems: resumeIds,
                                    verifiedNewSeasonIDs: libraryModel.verifiedNewSeasonIDs
                                )
                            },
                            imageURL: { libraryModel.imageURL(for: $0, wide: row.title == "Estás viendo") },
                            fallbackImageURL: row.title == "Estás viendo"
                                ? { libraryModel.imageURL(for: $0, wide: false) }
                                : nil,
                            onPlayDirect: { item in directItem = item },
                            onSeeAll: seeAllAction(for: row.title)
                        )

                        // Trending sits right after "Estás viendo" so fresh
                        // content shows up at the top of Home.
                        #if os(iOS) || os(macOS)
                        if index == 0 {
                            trendingShelf
                        }
                        #endif
                    }
                }

                // "Para ti" shelves: homogeneous rows after the library.
                #if os(iOS) || os(macOS)
                forYouShelf
                #endif
            }
            .padding(.top, MareaTheme.Spacing.md)
        }
        .background(MareaTheme.Colors.background)
        .refreshable {
            async let libraryReload: Void = libraryModel.load()
            #if os(iOS) || os(macOS)
            async let discoveryReload: Void = discovery?.loadRows() ?? ()
            _ = await (libraryReload, discoveryReload)
            #else
            await libraryReload
            #endif
        }
        .onAppear {
            // Refresh resume row whenever Home reappears (tab switch, pop back
            // from DetailView) so "Estás viendo" is never stale.
            Task { await libraryModel.refreshResume() }
        }

        #if os(macOS)
        return base.overlay {
            if let directItem {
                DirectPlayer(
                    item: directItem,
                    serverURL: serverURL,
                    token: token,
                    userId: userId,
                    onClosed: closeDirectPlayer
                )
                .ignoresSafeArea()
            }
        }
        #else
        return base.fullScreenCover(item: $directItem) { item in
            DirectPlayer(
                item: item,
                serverURL: serverURL,
                token: token,
                userId: userId,
                onClosed: closeDirectPlayer
            )
        }
        #endif
    }

    // MARK: - Premium home pieces

    #if os(iOS) || os(macOS)
    /// Netflix-style category chips (Películas, Series, …) — each opens the
    /// paginated grid for that server view.
    private var categoryChips: some View {
        Group {
            if !libraryModel.categoryChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MareaTheme.Spacing.sm) {
                        ForEach(libraryModel.categoryChips) { chip in
                            NavigationLink(value: chip) {
                                ChipView(title: chip.title)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, MareaTheme.Spacing.xl)
                }
            }
        }
    }

    #endif

    /// "Ver todo" target for a row backed by a server view. Rows without a
    /// matching category (resume, recently-watched) get no link. tvOS and
    /// visionOS have no LibraryGridView — always nil there.
    private func seeAllAction(for rowTitle: String) -> (() -> Void)? {
        #if os(iOS) || os(macOS)
        guard let chip = libraryModel.categoryChips.first(where: { $0.id == rowTitle }) else {
            return nil
        }
        return { navigationPath.append(chip) }
        #else
        return nil
        #endif
    }

    /// Big featured carousel on top of Home — up to 5 hero cards, swipable,
    /// with a "Reproducir" CTA that resumes playback directly.
    private func heroCarousel() -> some View {
        Group {
            if !libraryModel.heroItems.isEmpty {
                // viewAligned pages: one hero fills the width, the next one
                // peeks at the trailing edge (Netflix billboard feel).
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: MareaTheme.Spacing.md) {
                        ForEach(libraryModel.heroItems) { item in
                            HeroCardView(
                                item: item,
                                backdropURL: libraryModel.imageURL(for: item, wide: true),
                                posterURL: libraryModel.imageURL(for: item, wide: false),
                                onPlay: { directItem = item }
                            )
                            .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: MareaTheme.Spacing.md)
                            .transition(.opacity)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, MareaTheme.Spacing.md)
                }
                .scrollTargetBehavior(.viewAligned)
                .animation(.easeInOut(duration: 0.35), value: libraryModel.heroItems)
            } else if libraryModel.hasLoaded {
                // Coherent empty state instead of a silent gap.
                HeroEmptyStateView()
            }
        }
    }

    /// Player dismissed: back to this screen, then refresh progress rows
    /// once the reportStopped request has had time to land.
    private func closeDirectPlayer() {
        directItem = nil
        Task {
            try? await Task.sleep(for: .seconds(2))
            await libraryModel.refreshResume(force: true)
        }
    }
}
