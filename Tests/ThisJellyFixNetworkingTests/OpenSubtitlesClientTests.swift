import XCTest
@testable import ThisJellyFixNetworking
import ThisJellyFixCore

/// The app-side provider: a real client for the OpenSubtitles.com API.
///
/// The shapes below are the ones the provider really answers with (its own
/// reference client was the source): the search payload nests everything
/// under `attributes`, and the download is a POST with the `file_id` in the
/// query string.
final class OpenSubtitlesClientTests: XCTestCase {
    private let baseURL = URL(string: "https://api.opensubtitles.com")!

    /// The real shape of `GET /api/v1/subtitles`.
    private let searchJSON = """
    {
      "total_count": 2,
      "total_pages": 1,
      "per_page": 20,
      "page": 1,
      "data": [
        {
          "id": "8520224",
          "type": "subtitle",
          "attributes": {
            "subtitle_id": "8520224",
            "language": "es",
            "download_count": 147,
            "hearing_impaired": false,
            "ai_translated": false,
            "machine_translated": false,
            "release": "The Movie (1999)",
            "ratings": 4.6,
            "files": [ { "file_id": 987, "file_name": "The.Movie.es.srt" } ],
            "feature_details": {
              "title": "The Movie",
              "imdb_id": 111161,
              "season_number": 1,
              "episode_number": 3
            }
          }
        },
        {
          "id": 778899,
          "type": "subtitle",
          "attributes": {
            "subtitle_id": "778899",
            "language": "en",
            "ai_translated": true,
            "files": []
          }
        }
      ]
    }
    """

    // MARK: - Search

    func testSearchHitsTheDocumentedPathWithTheMandatoryHeaders() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(searchJSON.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "key-123", session: session, baseURL: baseURL)

        _ = try await client.search(OpenSubtitlesClient.SearchQuery(
            title: "The Movie",
            imdbId: "tt0111161",
            language: "es"
        ))

        let request = try XCTUnwrap(session.capturedRequests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/v1/subtitles")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["query"], "the movie")
        // The canonical form: the zero-padded id would make the provider's
        // gateway answer with a 301 that rewrites the value.
        XCTAssertEqual(items["imdb_id"], "111161")
        XCTAssertEqual(items["languages"], "es")

        XCTAssertEqual(request.value(forHTTPHeaderField: "Api-Key"), "key-123")
        XCTAssertFalse((request.value(forHTTPHeaderField: "User-Agent") ?? "").isEmpty)
    }

    /// The provider's gateway redirects when the query string is not sorted.
    func testQueryParametersAreSentSorted() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(searchJSON.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        _ = try await client.search(OpenSubtitlesClient.SearchQuery(
            title: "The Movie",
            imdbId: "tt0111161",
            seasonNumber: 1,
            episodeNumber: 3,
            language: "es"
        ))

        let request = try XCTUnwrap(session.capturedRequests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let names = (components.queryItems ?? []).map(\.name)
        XCTAssertEqual(names, names.sorted(), "query parameters must be sorted alphabetically")
    }

    /// The provider spells the episode filters `season_number` /
    /// `episode_number`; anything else is silently ignored and the search
    /// returns the whole series.
    func testEpisodeFiltersUseTheProviderNames() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(searchJSON.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        _ = try await client.search(OpenSubtitlesClient.SearchQuery(
            title: "The Series",
            parentImdbId: "tt0111161",
            seasonNumber: 3,
            episodeNumber: 7
        ))

        let request = try XCTUnwrap(session.capturedRequests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["season_number"], "3")
        XCTAssertEqual(items["episode_number"], "7")
        XCTAssertEqual(items["parent_imdb_id"], "111161")
        XCTAssertNil(items["season"])
        XCTAssertNil(items["episode"])
    }

    func testSearchDecodesTheAttributesShape() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(searchJSON.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        let results = try await client.search(OpenSubtitlesClient.SearchQuery(title: "The Movie"))

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].subtitleId, "8520224")
        XCTAssertEqual(results[0].fileId, 987)
        XCTAssertEqual(results[0].fileName, "The.Movie.es.srt")
        XCTAssertEqual(results[0].languageCode, "es")
        XCTAssertEqual(results[0].release, "The Movie (1999)")
        XCTAssertEqual(results[0].downloadCount, 147)
        XCTAssertEqual(results[0].rating, 4.6)
        XCTAssertFalse(results[0].machineTranslated)
        // A numeric id must decode too — the API is not consistent.
        XCTAssertEqual(results[1].subtitleId, "778899")
        XCTAssertTrue(results[1].machineTranslated)
    }

    /// The flat shape is still accepted, so an older gateway does not empty
    /// the list.
    func testSearchAlsoAcceptsTheFlatShape() async throws {
        let flat = """
        { "data": [ { "id": "1", "language_code": "spa", "release": "X", "download_count": 3,
                      "rating": 4.1, "files": [ { "file_id": 42, "file_name": "x.srt" } ] } ] }
        """
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(flat.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        let results = try await client.search(OpenSubtitlesClient.SearchQuery(title: "X"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].fileId, 42)
        XCTAssertEqual(results[0].languageCode, "spa")
        XCTAssertEqual(results[0].downloadCount, 3)
    }

    func testSearchWithoutAnyCriteriaIsRejected() async {
        let session = ScriptedNetworkSession(responses: [])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        do {
            _ = try await client.search(OpenSubtitlesClient.SearchQuery())
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? OpenSubtitlesError, .missingQuery)
        }
    }

    // MARK: - Errors

    func testRejectedKeyMapsToInvalidAPIKey() async {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data("{\"message\":\"Invalid API key\"}".utf8), statusCode: 403)
        ])
        let client = OpenSubtitlesClient(apiKey: "bad", session: session, baseURL: baseURL)

        do {
            _ = try await client.search(OpenSubtitlesClient.SearchQuery(title: "x"))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? OpenSubtitlesError, .invalidAPIKey)
        }
    }

    func testRateLimitIsReported() async {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(), statusCode: 429)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        do {
            _ = try await client.search(OpenSubtitlesClient.SearchQuery(title: "x"))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? OpenSubtitlesError, .rateLimited)
        }
    }

    func testServerErrorCarriesTheStatus() async {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(), statusCode: 503)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        do {
            _ = try await client.search(OpenSubtitlesClient.SearchQuery(title: "x"))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? OpenSubtitlesError, .serverError(503))
        }
    }

    // MARK: - Download

    /// The download is a POST with the `file_id` in the query string — the
    /// id of the concrete file, which a subtitle can bundle several of.
    func testDownloadPostsTheFileIdAndUnzipsTheFile() async throws {
        let linkJSON = """
        { "link": "https://dl.opensubtitles.com/file.srt.gz", "file_name": "The.Movie.es.srt", "remaining": 99 }
        """
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(linkJSON.utf8), statusCode: 200),
            .init(data: Data(Self.gzipFixture), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        let file = try await client.download(fileId: 987)

        XCTAssertEqual(file.text, Self.plainFixture)
        XCTAssertEqual(file.format, "srt")
        XCTAssertEqual(file.fileName, "The.Movie.es.srt")

        XCTAssertEqual(session.capturedRequests.count, 2)
        let first = try XCTUnwrap(session.capturedRequests[0].url)
        XCTAssertEqual(first.path, "/api/v1/download")
        let components = try XCTUnwrap(URLComponents(url: first, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["file_id"], "987")
        XCTAssertEqual(session.capturedRequests[0].httpMethod, "POST")

        let second = try XCTUnwrap(session.capturedRequests[1].url)
        XCTAssertEqual(second.absoluteString, "https://dl.opensubtitles.com/file.srt.gz")
        // The API key never travels to the CDN.
        XCTAssertNil(session.capturedRequests[1].value(forHTTPHeaderField: "Api-Key"))
    }

    func testDownloadAcceptsAPlainFileToo() async throws {
        let linkJSON = """
        { "link": "https://dl.opensubtitles.com/file.srt", "file_name": "The.Movie.es.srt" }
        """
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(linkJSON.utf8), statusCode: 200),
            .init(data: Data(Self.plainFixture.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        let file = try await client.download(fileId: 1)
        XCTAssertEqual(file.text, Self.plainFixture)
    }

    func testDownloadWithoutALinkIsRejected() async {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data("{}".utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        do {
            _ = try await client.download(fileId: 1)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? OpenSubtitlesError, .malformedResponse)
        }
    }

    /// A payload that claims to be gzip but cannot be inflated is broken.
    /// It must NOT reach the server as if it were a subtitle.
    func testBrokenCompressedPayloadIsRejected() async {
        let linkJSON = """
        { "link": "https://dl.opensubtitles.com/file.srt.gz", "file_name": "x.srt" }
        """
        // Gzip magic followed by garbage: the header is broken.
        let broken: [UInt8] = [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0x01, 0x02]
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(linkJSON.utf8), statusCode: 200),
            .init(data: Data(broken), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        do {
            _ = try await client.download(fileId: 1)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? OpenSubtitlesError, .compressedPayloadUnreadable)
        }
    }

    // MARK: - Connection test

    func testConnectionProbePerformsARealSearch() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(searchJSON.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        let count = try await client.testConnection()
        XCTAssertEqual(count, 2)
        let request = try XCTUnwrap(session.capturedRequests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertNotNil(items["query"])
    }

    // MARK: - Format

    func testFormatIsReadFromTheFileName() {
        XCTAssertEqual(OpenSubtitlesClient.format(fromFileName: "a.b.srt"), "srt")
        XCTAssertEqual(OpenSubtitlesClient.format(fromFileName: "a.b.vtt"), "vtt")
        XCTAssertEqual(OpenSubtitlesClient.format(fromFileName: "a.b.ass"), "ass")
        XCTAssertEqual(OpenSubtitlesClient.format(fromFileName: nil), "srt")
        XCTAssertEqual(OpenSubtitlesClient.format(fromFileName: "a.b.unknown"), "srt")
    }

    func testCanonicalImdbId() {
        XCTAssertEqual(OpenSubtitlesClient.canonicalImdbId("tt0111161"), "111161")
        XCTAssertEqual(OpenSubtitlesClient.canonicalImdbId("tt-0111161"), "111161")
        XCTAssertEqual(OpenSubtitlesClient.canonicalImdbId("tt_0111161"), "111161")
        XCTAssertEqual(OpenSubtitlesClient.canonicalImdbId("0111161"), "111161")
        XCTAssertEqual(OpenSubtitlesClient.canonicalImdbId("111161"), "111161")
        XCTAssertEqual(OpenSubtitlesClient.canonicalImdbId("tt0000001"), "1")
        XCTAssertNil(OpenSubtitlesClient.canonicalImdbId(""))
        XCTAssertNil(OpenSubtitlesClient.canonicalImdbId("not-an-id"))
    }

    func testCanonicalNumericId() {
        XCTAssertEqual(OpenSubtitlesClient.canonicalNumericId("0133552"), "133552")
        XCTAssertEqual(OpenSubtitlesClient.canonicalNumericId("133552"), "133552")
        XCTAssertNil(OpenSubtitlesClient.canonicalNumericId("abc"))
    }

    // MARK: - Fixtures

    private static let plainFixture = "1\n00:00:01,000 --> 00:00:02,000\nHola\n\n"

    /// gzip of `plainFixture` (the API serves the file compressed).
    private static let gzipFixture: [UInt8] = [
        31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 51, 228, 50, 48, 176, 2, 33, 67, 29, 3, 3, 3, 5, 93, 93, 59, 5,
        168, 128, 17, 72, 128, 203, 35, 63, 39, 145, 139, 11, 0, 167, 3, 179, 140, 38, 0, 0, 0
    ]
}

// MARK: - Helpers

/// Replays queued responses and records the requests that were made.
final class ScriptedNetworkSession: JellyfinNetworkSession, @unchecked Sendable {
    struct Response {
        let data: Data
        let statusCode: Int
    }

    private let responses: [Response]
    private let lock = NSLock()
    private var index = 0
    private var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    var capturedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(request)
        let current = index
        index += 1
        lock.unlock()

        let response = current < responses.count
            ? responses[current]
            : Response(data: Data(), statusCode: 500)
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response.data, http)
    }
}
