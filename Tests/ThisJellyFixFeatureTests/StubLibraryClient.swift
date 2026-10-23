import XCTest
@testable import ThisJellyFixCore
import ThisJellyFixNetworking
@testable import ThisJellyFixFeature

/// Scriptable library client — feeds `load()` with fixed rows.
///
/// `LibraryModel.load()` fetches its rows CONCURRENTLY, so this stub is hit
/// from several threads at once: every mutable piece needs a lock, or the
/// concurrent appends race and corrupt the heap (it used to crash the test
/// process with SIGSEGV, roughly one run in twenty).
final class StubLibraryClient: JellyfinLibraryProviding, @unchecked Sendable {
    var views: [LibraryView] = []
    var resumeItems: [JellyfinMediaItem] = []
    var latestItems: [JellyfinMediaItem] = []
    var fetchItemsError: Error?

    /// Guards the mutable state below.
    private let lock = NSLock()
    private var _recordedStartIndices: [Int?] = []

    /// Start indices of every `fetchItems` call, in no particular order.
    var recordedStartIndices: [Int?] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedStartIndices
    }

    func fetchViews(userId: String, serverURL: URL, token: String) async throws -> [LibraryView] {
        views
    }

    func fetchItems(
        userId: String, serverURL: URL, token: String,
        parentId: String?, includeTypes: String?,
        limit: Int, orderBy: String, filters: String?, startIndex: Int?
    ) async throws -> [JellyfinMediaItem] {
        lock.lock()
        _recordedStartIndices.append(startIndex)
        lock.unlock()
        if let fetchItemsError { throw fetchItemsError }
        return latestItems
    }

    func searchItems(
        userId: String, serverURL: URL, token: String,
        query: String, includeTypes: String?, limit: Int
    ) async throws -> [JellyfinMediaItem] {
        []
    }

    func fetchSeasons(userId: String, serverURL: URL, token: String, seriesId: String) async throws -> [JellyfinSeason] {
        []
    }

    func fetchEpisodes(
        userId: String, serverURL: URL, token: String,
        seriesId: String, seasonId: String
    ) async throws -> [JellyfinEpisode] {
        []
    }

    func fetchResumeItems(userId: String, serverURL: URL, token: String, limit: Int) async throws -> [JellyfinMediaItem] {
        resumeItems
    }
}
