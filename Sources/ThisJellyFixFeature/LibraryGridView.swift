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
                                    flexibleWidth: true
                                )
                            }
                            .buttonStyle(.plain)
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
            items = []
            nextStartIndex = nil
            hasMore = true
            await loadFirstPage()
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
            await loadNextPage()
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

    private func loadFirstPage() async {
        guard !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        let page = await model.fetchPage(
            parentId: parentId,
            includeTypes: includeTypes,
            limit: pageSize,
            startIndex: nil
        )
        items = page
        hasMore = page.count == pageSize
        nextStartIndex = page.count
    }
}
#endif
