import XCTest
@testable import ThisJellyFixCore
import ThisJellyFixNetworking
@testable import ThisJellyFixFeature

/// Scriptable library client — feeds `load()` with fixed rows.
final class StubLibraryClient: JellyfinLibraryProviding, @unchecked Sendable {
    var views: [LibraryView] = []
    var resumeItems: [JellyfinMediaItem] = []
    var latestItems: [JellyfinMediaItem] = []
    private(set) var recordedStartIndices: [Int?] = []

    func fetchViews(userId: String, serverURL: URL, token: String) async throws -> [LibraryView] {
        views
    }

    func fetchItems(
        userId: String, serverURL: URL, token: String,
        parentId: String?, includeTypes: String?,
        limit: Int, orderBy: String, filters: String?, startIndex: Int?
    ) async throws -> [JellyfinMediaItem] {
        recordedStartIndices.append(startIndex)
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
