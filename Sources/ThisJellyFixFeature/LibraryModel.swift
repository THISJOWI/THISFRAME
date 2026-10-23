import Foundation
import Observation
import ThisJellyFixCore
import ThisJellyFixNetworking

struct ContentRow: Identifiable, Hashable {
    /// Stable identity: a refresh replaces `items` under the same row, so the
    /// view updates in place instead of tearing down every card (and its image).
    let id: String
    let title: String
    let items: [JellyfinMediaItem]

    init(title: String, items: [JellyfinMediaItem]) {
        self.id = title
        self.title = title
        self.items = items
    }

    static func == (lhs: ContentRow, rhs: ContentRow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Home category chip backed by a server view (Películas, Series, …).
struct CategoryChip: Identifiable, Equatable, Hashable {
    /// Display title doubles as identity (chips come from server view names).
    let id: String
    let title: String
    let parentId: String?
    let includeTypes: String?
}

@MainActor
@Observable
final class LibraryModel {
    var rows: [ContentRow] = []
    var isLoading = false
    var errorMessage: String?
    /// Every distinct item across the loaded rows — the discovery layer
    /// matches TMDB ids against this set to know what the library owns.
    var allItems: [JellyfinMediaItem] {
        var seen = Set<String>()
        return rows.flatMap(\.items).filter { seen.insert($0.id).inserted }
    }
    /// E4: the server answered 401 — the token is gone. Retrying can never
    /// succeed, so the UI offers "Cerrar sesión" instead of a dead "Reintentar".
    var sessionExpired = false

    /// Handoff: set by the root view when a Handoff continuation resolves to a
    /// known library item. HomeView consumes this value immediately by pushing
    /// it onto the NavigationStack, then resets it to nil.
    var pendingNavigationItem: JellyfinMediaItem?
    /// Handoff playback position (seconds) to resume at once DetailView opens.
    /// nil = plain detail navigation (no autoplay).
    var pendingNavigationPosition: Double?

    /// True once `load()` has completed (all rows in). Handoff resolution
    /// waits for this — resolving against a not-yet-loaded library was the
    /// cold-launch "Dock → app → nothing" bug.
    var hasLoaded = false

    /// Series ids whose "Nueva temporada" was verified by comparing the series
    /// creation date against its seasons' dates (NoveltyClassifier). Cards
    /// only show the badge for ids in this set — never for unwatched series.
    private(set) var verifiedNewSeasonIDs: Set<String> = []

    /// Folder ids of the server views found during `load()`.
    private(set) var moviesParentId: String?
    private(set) var seriesParentId: String?

    /// Category chips for the Home header — one per known server view.
    /// Each chip opens a LibraryGridView filtered to that collection.
    var categoryChips: [CategoryChip] {
        var chips: [CategoryChip] = []
        if let moviesParentId {
            chips.append(CategoryChip(
                id: "Películas", title: "Películas",
                parentId: moviesParentId, includeTypes: "Movie"
            ))
        }
        if let seriesParentId {
            chips.append(CategoryChip(
                id: "Series", title: "Series",
                parentId: seriesParentId, includeTypes: "Series"
            ))
        }
        return chips
    }

    private let libraryClient: any JellyfinLibraryProviding
    private let serverURL: URL
    private let userId: String
    private let token: String

    init(
        libraryClient: any JellyfinLibraryProviding = JellyfinLibraryClient(),
        serverURL: URL,
        userId: String,
        token: String
    ) {
        self.libraryClient = libraryClient
        self.serverURL = serverURL
        self.userId = userId
        self.token = token
    }

    /// Canonical row order. Rows publish as their fetches land, so each insert
    /// re-sorts into place.
    private static let rowOrder = [
        "Estás viendo", "Nuevos episodios", "Últimos agregados", "Películas", "Series", "Visto recientemente",
    ]

    /// Minimum gap between resume-row refreshes: Home reappears several times
    /// in a row (tab switch, pop back from detail), each with its own trigger,
    /// which used to fire the same `/Items/Resume` GET back to back.
    private static let resumeRefreshCooldown: TimeInterval = 5
    private var lastResumeRefresh: Date?
    /// True while a resume fetch is in flight — drives the row refresh
    /// spinner and collapses concurrent manual taps into one request.
    var isRefreshingResume = false

    func load() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            // M4: `hasLoaded` means "usable library", not "load() returned".
            // A failed cold launch (0 rows + error) must NOT flip this — the
            // Handoff resolver would see .loaded(itemCount: 0), consume the
            // pending intent as .notFound and reproduce "Dock → app → nothing"
            // (retry can no longer recover it). Partial loads (some rows)
            // count as loaded: a found item resolves, only a genuinely
            // absent one is consumed.
            hasLoaded = !rows.isEmpty
        }

        // Views first: the Movies/Series rows need their folder ids. Everything
        // else is independent, so the row fetches run IN PARALLEL and each row
        // appears the moment it lands instead of after the slowest request.
        var moviesParent: String?
        var seriesParent: String?
        do {
            let views = try await libraryClient.fetchViews(
                userId: userId, serverURL: serverURL, token: token
            )
            moviesParent = views.first(where: { $0.collectionType == "movies" })?.id
            seriesParent = views.first(where: { $0.collectionType == "tvshows" })?.id
            // Expose for the Home category chips + "Ver todo" targets.
            moviesParentId = moviesParent
            seriesParentId = seriesParent
        } catch {
            // Only the two folder-backed rows are lost; the rest still load.
            noteFetchFailure(error, context: "fetchViews", surfaceMessage: true)
        }

        let client = libraryClient
        let serverURL = self.serverURL
        let userId = self.userId
        let token = self.token

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadResumeAndNextUpRow() }
            group.addTask { await self.loadNewEpisodesRow() }
            group.addTask { await self.loadRow("Últimos agregados") {
                try await client.fetchItems(
                    userId: userId, serverURL: serverURL, token: token,
                    parentId: nil, includeTypes: "Movie,Series",
                    limit: 20, orderBy: "DateCreated", filters: nil
                )
            } }
            if let moviesParent {
                group.addTask { await self.loadRow("Películas") {
                    try await client.fetchItems(
                        userId: userId, serverURL: serverURL, token: token,
                        parentId: moviesParent, includeTypes: "Movie",
                        limit: 20, orderBy: "DateCreated", filters: nil
                    )
                } }
            }
            if let seriesParent {
                group.addTask { await self.loadRow("Series") {
                    try await client.fetchItems(
                        userId: userId, serverURL: serverURL, token: token,
                        parentId: seriesParent, includeTypes: "Series",
                        limit: 20, orderBy: "DateCreated", filters: nil
                    )
                } }
            }
            group.addTask { await self.loadRow("Visto recientemente") {
                try await client.fetchItems(
                    userId: userId, serverURL: serverURL, token: token,
                    parentId: nil, includeTypes: "Movie,Series",
                    limit: 20, orderBy: "DateCreated", filters: "IsPlayed"
                )
            } }
        }

        if rows.isEmpty, errorMessage == nil {
            errorMessage = "No se pudo cargar la biblioteca."
        } else if !rows.isEmpty {
            SpotlightIndexer.shared.index(allItems, serverURL: serverURL)
            await verifyNewSeasons()
        }
    }

    /// Loads "Estás viendo" by merging /Items/Resume with /Shows/NextUp.
    ///
    /// Resume items carry an in-progress position — they come first.
    /// NextUp items represent the *next* unwatched episode for a series where
    /// the viewer just finished the previous one (so /Items/Resume shows
    /// nothing for that series). They are appended after, deduplicated by
    /// series so a series already in the resume list isn't doubled.
    private func loadResumeAndNextUpRow() async {
        do {
            // Both requests run in parallel — the merge waits for both.
            async let resumeFetch = libraryClient.fetchResumeItems(
                userId: userId, serverURL: serverURL, token: token, limit: 20
            )
            async let nextUpFetch = libraryClient.fetchNextUp(
                userId: userId, serverURL: serverURL, token: token, limit: 20
            )
            let resumeItems = try await resumeFetch
            // Resume is the primary source. If NextUp is unavailable (older
            // server, transient endpoint failure), keep its authoritative
            // progress row visible instead of dropping the whole section.
            let nextUpItems = (try? await nextUpFetch) ?? []

            // Build the merged list: resume items first (preserve order), then
            // NextUp items whose series are not already represented in resume.
            // Items are keyed by their own id for resume; by seriesName for NextUp
            // (the NextUp DTO carries SeriesName but not the series id in this
            // endpoint — deduplicate on that instead of risking a missing field).
            var seen = Set<String>()
            var merged: [JellyfinMediaItem] = []
            for item in resumeItems {
                seen.insert(item.id)
                // For episodes: also mark the series as represented so NextUp
                // doesn't add a second card for the same show.
                if let sn = item.seriesName { seen.insert("series:\(sn)") }
                merged.append(item)
            }
            for item in nextUpItems {
                // Skip if the exact episode is already in the resume list.
                guard !seen.contains(item.id) else { continue }
                // Skip if the same series is already shown (don't double-up).
                if let sn = item.seriesName {
                    guard !seen.contains("series:\(sn)") else { continue }
                    seen.insert("series:\(sn)")
                }
                seen.insert(item.id)
                merged.append(item)
            }

            TJFLog("loadResumeAndNextUpRow: resume=\(resumeItems.count) nextUp=\(nextUpItems.count) merged=\(merged.count)")
            lastResumeRefresh = Date()
            publish(ContentRow(title: "Estás viendo", items: merged))
        } catch {
            noteFetchFailure(error, context: "Estás viendo row", surfaceMessage: false)
        }
    }

    /// "Nuevos episodios": episodes incorporated today (verified via
    /// DateCreated on the same calendar day). Published only when at least
    /// one qualifies — an empty row is never shown, and old incorporations
    /// are not dressed up as news.
    private func loadNewEpisodesRow() async {
        do {
            let episodes = try await libraryClient.fetchItems(
                userId: userId, serverURL: serverURL, token: token,
                parentId: nil, includeTypes: "Episode",
                limit: 20, orderBy: "DateCreated", filters: nil
            )
            let classifier = NoveltyClassifier()
            let todays = episodes.filter {
                classifier.novelty(for: $0) == .newEpisodeToday
            }
            TJFLog("load: Nuevos episodios total=\(episodes.count) today=\(todays.count)")
            publish(ContentRow(title: "Nuevos episodios", items: todays))
        } catch {
            // Degrade silently: novelty is decoration, never blocking.
            TJFLog("load: Nuevos episodios FAILED: \(error.localizedDescription)")
        }
    }

    /// Verifies "Nueva temporada" for candidate series (older than the window
    /// with recent media additions) by fetching their seasons and comparing
    /// dates. Bounded work: only candidates pass the cheap pre-filter, and a
    /// failed verification simply withholds the badge — it never guesses.
    private func verifyNewSeasons() async {
        let classifier = NoveltyClassifier()
        let candidates = allItems.filter { classifier.isSeasonCandidate($0) }
        guard !candidates.isEmpty else { return }

        let client = libraryClient
        let serverURL = self.serverURL
        let userId = self.userId
        let token = self.token
        let verified = await withTaskGroup(of: String?.self) { group -> Set<String> in
            for series in candidates.prefix(10) {
                group.addTask {
                    guard let seasons = try? await client.fetchSeasons(
                        userId: userId, serverURL: serverURL, token: token,
                        seriesId: series.id
                    ) else { return nil }
                    return classifier.hasVerifiedNewSeason(
                        seriesDateCreated: series.dateCreated, seasons: seasons
                    ) ? series.id : nil
                }
            }
            var ids = Set<String>()
            for await id in group {
                if let id { ids.insert(id) }
            }
            return ids
        }
        if !verified.isEmpty {
            verifiedNewSeasonIDs.formUnion(verified)
            TJFLog("verifyNewSeasons verified=\(verified.sorted().joined(separator: ","))")
        }
    }

    /// Fetch one row alongside its siblings and publish it as soon as it lands.
    /// A failing row degrades to a logged gap — it never discards the rows that
    /// already arrived (the old all-or-nothing behaviour lost five responses
    /// when the sixth request timed out).
    private func loadRow(
        _ title: String,
        _ fetch: @Sendable @escaping () async throws -> [JellyfinMediaItem]
    ) async {
        do {
            let items = try await fetch()
            TJFLog("load: \(title) items=\(items.count)")
            if title == "Estás viendo" { lastResumeRefresh = Date() }
            publish(ContentRow(title: title, items: items))
        } catch {
            noteFetchFailure(error, context: "\(title) row", surfaceMessage: false)
        }
    }

    private func publish(_ row: ContentRow) {
        rows.removeAll { $0.id == row.id }
        // A successful empty response means this shelf is now empty. Keeping
        // its previous value made removed/played items survive every refresh.
        guard !row.items.isEmpty else { return }
        rows.append(row)
        rows.sort {
            let l = Self.rowOrder.firstIndex(of: $0.title) ?? Self.rowOrder.count
            let r = Self.rowOrder.firstIndex(of: $1.title) ?? Self.rowOrder.count
            return l == r ? $0.title < $1.title : l < r
        }
    }

    /// Refresh ONLY the "Estás viendo" row without touching the rest of the UI.
    /// Used when returning to Home or shortly after the player dismisses.
    /// Coalesced: repeated appearances within `resumeRefreshCooldown` share one
    /// request instead of firing the same GET over and over.
    ///
    /// - Parameter force: the refresh that matters — after playback, the row
    ///   must show the NEW progress. Without this, the appearance trigger that
    ///   fires a moment earlier (still holding the old progress) stamps the
    ///   cooldown and the authoritative refresh is silently dropped: the row
    ///   keeps the pre-playback state and the user "loses" their progress.
    func refreshResume(force: Bool = false) async {
        // A load() is already fetching every row, including this one — but a
        // FORCED refresh is the authoritative post-playback update: a resume
        // fetch does not conflict with `load()` (it overwrites the same row),
        // and dropping it is what made the row keep the old progress.
        if !force, isLoading { return }
        if !force, let last = lastResumeRefresh, Date().timeIntervalSince(last) < Self.resumeRefreshCooldown {
            return
        }
        // Manual taps share one request instead of stacking GETs — but a
        // FORCED refresh always runs: it is the authoritative post-playback
        // update and must not be dropped by a stale fetch in flight.
        if !force, isRefreshingResume { return }
        isRefreshingResume = true
        defer { isRefreshingResume = false }
        let stampedAt = Date()
        // Stamp before the request so concurrent NON-forced triggers don't stack.
        lastResumeRefresh = stampedAt
        do {
            // Run Resume and NextUp in parallel; merge as in loadResumeAndNextUpRow.
            async let resumeFetch = libraryClient.fetchResumeItems(
                userId: userId, serverURL: serverURL, token: token, limit: 20
            )
            async let nextUpFetch = libraryClient.fetchNextUp(
                userId: userId, serverURL: serverURL, token: token, limit: 20
            )
            let resumeItems = try await resumeFetch
            // A NextUp failure should not hide Resume items during refresh.
            let nextUpItems = (try? await nextUpFetch) ?? []

            // Stamp again on success: a slow/stale response must not count as
            // "fresh data" for the next request within the cooldown window.
            lastResumeRefresh = Date()

            var seen = Set<String>()
            var merged: [JellyfinMediaItem] = []
            for item in resumeItems {
                seen.insert(item.id)
                if let sn = item.seriesName { seen.insert("series:\(sn)") }
                merged.append(item)
            }
            for item in nextUpItems {
                guard !seen.contains(item.id) else { continue }
                if let sn = item.seriesName {
                    guard !seen.contains("series:\(sn)") else { continue }
                    seen.insert("series:\(sn)")
                }
                seen.insert(item.id)
                merged.append(item)
            }

            TJFLog("refreshResume resume=\(resumeItems.count) nextUp=\(nextUpItems.count) merged=\(merged.count) force=\(force)")
            if let idx = rows.firstIndex(where: { $0.title == "Estás viendo" }) {
                if merged.isEmpty {
                    rows.remove(at: idx)
                } else {
                    rows[idx] = ContentRow(title: "Estás viendo", items: merged)
                }
            } else if !merged.isEmpty {
                rows.insert(ContentRow(title: "Estás viendo", items: merged), at: 0)
            }
        } catch {

            // A failed request must NOT burn the cooldown: the pre-stamp above
            // exists only to coalesce concurrent triggers, and leaving it set
            // after an error silently dropped the next natural refresh —
            // which is how "Estás viendo" stayed stale and episodes started in
            // another app never showed up. Only OUR stamp is cleared, never a
            // newer one a concurrent refresh already replaced it with.
            if lastResumeRefresh == stampedAt {
                lastResumeRefresh = nil
            }
            noteFetchFailure(error, context: "refreshResume", surfaceMessage: false)
        }
    }

    /// Records a failed fetch: always logs; surfaces the message only for the
    /// callers that own the error UI, and marks the session dead on 401 so the
    /// screen can offer a logout that works instead of a retry that never will.
    private func noteFetchFailure(_ error: Error, context: String, surfaceMessage: Bool) {
        TJFLog("load: \(context) FAILED: \(error.localizedDescription)")
        if let libraryError = error as? LibraryError, libraryError == .unauthorized {
            sessionExpired = true
            errorMessage = libraryError.errorDescription ?? error.localizedDescription
            return
        }
        if surfaceMessage {
            errorMessage = error.localizedDescription
        }
    }

    /// One page of library items for the "Ver todo" grid. The caller tracks
    /// `startIndex` and stops when a page returns fewer than `limit` items.
    func fetchPage(
        parentId: String?,
        includeTypes: String?,
        limit: Int = 30,
        startIndex: Int? = nil
    ) async -> [JellyfinMediaItem] {
        do {
            return try await libraryClient.fetchItems(
                userId: userId, serverURL: serverURL, token: token,
                parentId: parentId, includeTypes: includeTypes,
                limit: limit, orderBy: "DateCreated", filters: nil,
                startIndex: startIndex
            )
        } catch {
            noteFetchFailure(error, context: "fetchPage", surfaceMessage: false)
            return []
        }
    }

    /// Artwork for a card showing `item`.
    ///
    /// Episodes are always 16:9 frames (their card is landscape) and
    /// everything else a 2:3 poster, so the picture asked for always
    /// matches the box it is drawn in. `wide: true` forces the landscape
    /// variant for the items that are not episodes — the "continue
    /// watching" row.
    func imageURL(for item: JellyfinMediaItem, wide: Bool = false) -> URL? {
        item.artworkURL(serverURL: serverURL, shape: wide ? .landscape : nil)
    }

    /// The item's portrait poster, cropped to a 2:3 box. Used as the
    /// fallback when a landscape frame cannot be fetched.
    func posterURL(for item: JellyfinMediaItem) -> URL? {
        item.artworkURL(serverURL: serverURL, shape: .poster)
    }
}
