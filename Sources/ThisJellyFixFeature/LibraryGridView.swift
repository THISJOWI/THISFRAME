import SwiftUI
import ThisJellyFixCore

/// Paginated grid behind a row's "Ver todo" link. Loads pages of 30 and
/// fetches the next page when the last cell appears.
///
/// iOS/macOS only — tvOS/visionOS rows hide "Ver todo".
#if os(iOS) || os(macOS)
struct LibraryGridView: View {
    let title: String
    let parentId: String?
    let includeTypes: String?
    let serverURL: URL
    let token: String
    let userId: String

    /// Own model instance: the grid pages through one library slice without
    /// touching the Home rows state.
    @State private var model: LibraryModel
    @State private var items: [JellyfinMediaItem] = []
    @State private var nextStartIndex: Int? = nil
    @State private var isLoadingPage = false
    /// A refresh is a separate request from a page load: it must not be
    /// swallowed by a page that happens to be in flight.
    @State private var isRefreshing = false
    @State private var hasMore = true

    private let pageSize = 30

    init(
        title: String,
        parentId: String?,
        includeTypes: String?,
        serverURL: URL,
        token: String,
        userId: String
    ) {
        self.title = title
        self.parentId = parentId
        self.includeTypes = includeTypes
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        _model = State(initialValue: LibraryModel(
            serverURL: serverURL, userId: userId, token: token
        ))
    }

    private var columns: [GridItem] {
        #if os(macOS)
        // Desktop: larger posters so the grid fills the window sensibly.
        [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: MareaTheme.Spacing.md)]
        #else
        [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: MareaTheme.Spacing.md)]
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: MareaTheme.Spacing.lg) {
                if items.isEmpty && isLoadingPage {
                    LazyVGrid(columns: columns, spacing: MareaTheme.Spacing.md) {
                        ForEach(0..<12, id: \.self) { _ in
                            SkeletonView(
                                width: 0,
                                height: 0,
                                aspectRatio: MediaCardLayout.Shape.poster.aspectRatio
                            )
                        }
                    }
                    .padding(.horizontal, MareaTheme.Spacing.md)
                } else {
                    LazyVGrid(columns: columns, spacing: MareaTheme.Spacing.md) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item) {
                                MediaCardView(
                                    item: item,
                                    imageURL: model.imageURL(for: item),
                                    // The grid column decides the width: a
                                    // fixed card size would overflow the cell.
                                    flexibleWidth: true,
                                    // Grid cells appear as the user scrolls:
                                    // they show up already in place.
                                    revealWithRow: false
                                )
                            }
                            .buttonStyle(PressableCardStyle())
                            .onAppear {
                                // Kick the next page when the trailing cell shows.
                                if index >= items.count - 6 {
                                    loadNextPage()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, MareaTheme.Spacing.md)

                    if isLoadingPage {
                        ProgressView()
                            .padding(.vertical, MareaTheme.Spacing.lg)
                    }
                }
            }
            .padding(.vertical, MareaTheme.Spacing.md)
        }
        .background(MareaTheme.Colors.background)
        .refreshable {
            // Reload the first page IN PLACE: emptying the grid would blank
            // the screen and throw the scroll position away.
            await reloadFirstPage()
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .navigationDestination(for: JellyfinMediaItem.self) { item in
            DetailView(item: item, serverURL: serverURL, token: token, userId: userId)
        }
        .task {
            guard items.isEmpty else { return }
            await reloadFirstPage()
        }
    }

    private func loadNextPage() {
        guard !isLoadingPage, hasMore else { return }
        isLoadingPage = true
        let start = nextStartIndex
        Task {
            let page = await model.fetchPage(
                parentId: parentId,
                includeTypes: includeTypes,
                limit: pageSize,
                startIndex: start
            )
            items.append(contentsOf: page)
            hasMore = page.count == pageSize
            nextStartIndex = (nextStartIndex ?? 0) + page.count
            isLoadingPage = false
        }
    }

    /// Fetch the first page and refresh what is on screen.
    ///
    /// The grid keeps showing what it has while the request is in flight —
    /// the user never sees an empty screen, and the scroll position survives.
    /// The pages the user already scrolled through are kept: only the first
    /// page is re-read.
    private func reloadFirstPage() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let page = await model.fetchPage(
            parentId: parentId,
            includeTypes: includeTypes,
            limit: pageSize,
            startIndex: nil
        )
        if items.count <= page.count {
            items = page
        } else {
            // Keep the pages already loaded below the refreshed first one.
            items.replaceSubrange(0..<page.count, with: page)
        }
        hasMore = page.count == pageSize
        // The pagination cursor only moves on the first load: a refresh
        // re-reads the first page, it does not restart the pagination.
        if nextStartIndex == nil {
            nextStartIndex = page.count
        }
    }
}
#endif
