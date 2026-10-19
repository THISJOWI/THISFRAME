import XCTest
@testable import ThisJellyFixNetworking
import ThisJellyFixCore

/// The app-side provider: a real client for the OpenSubtitles.com API.
final class OpenSubtitlesClientTests: XCTestCase {
    private let baseURL = URL(string: "https://api.opensubtitles.com")!

    private let searchJSON = """
    {
      "total_count": 2,
      "page": 1,
      "data": [
        {
          "id": "5512345",
          "type": "subtitle",
          "language": "Spanish",
          "language_code": "spa",
          "language_name": "Spanish",
          "hearing_impaired": false,
          "forced": false,
          "ai_translated": false,
          "release": "The Movie (1999)",
          "download_count": 421,
          "rating": 4.6,
          "files": [ { "file_id": 987, "file_name": "The.Movie.spa.srt", "file_size": 1234 } ]
        },
        {
          "id": 778899,
          "language_code": "eng",
          "release": "The Movie (1999) Director's Cut",
          "ai_translated": true,
          "files": []
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
        XCTAssertEqual(items["query"], "The Movie")
        // The canonical form: the zero-padded id would make the provider's
        // gateway answer with a 301 that rewrites the value.
        XCTAssertEqual(items["imdb_id"], "111161")
        XCTAssertEqual(items["languages"], "es")

        XCTAssertEqual(request.value(forHTTPHeaderField: "Api-Key"), "key-123")
        XCTAssertFalse((request.value(forHTTPHeaderField: "User-Agent") ?? "").isEmpty)
    }

    func testSearchDecodesTheResults() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(searchJSON.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        let results = try await client.search(OpenSubtitlesClient.SearchQuery(title: "The Movie"))

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].subtitleId, "5512345")
        XCTAssertEqual(results[0].fileId, 987)
        XCTAssertEqual(results[0].fileName, "The.Movie.spa.srt")
        XCTAssertEqual(results[0].languageCode, "spa")
        XCTAssertEqual(results[0].downloadCount, 421)
        XCTAssertEqual(results[0].rating, 4.6)
        XCTAssertFalse(results[0].machineTranslated)
        // A numeric id must decode too — the API is not consistent.
        XCTAssertEqual(results[1].subtitleId, "778899")
        XCTAssertTrue(results[1].machineTranslated)
    }

    /// The provider's gateway answers 301 when the query string is not
    /// canonical. The client must send the canonical form directly so the
    /// request (and the API key) is not split in two.
    func testQueryParametersAreSentSorted() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(searchJSON.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        _ = try await client.search(OpenSubtitlesClient.SearchQuery(
            title: "The Movie",
            imdbId: "tt0111161",
            season: 1,
            episode: 3,
            language: "es"
        ))

        let request = try XCTUnwrap(session.capturedRequests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let names = (components.queryItems ?? []).map(\.name)
        XCTAssertEqual(names, names.sorted(), "query parameters must be sorted alphabetically")
        XCTAssertEqual(names, ["episode", "imdb_id", "languages", "query", "season"])
    }

    /// The zero-padded Imdb id is rewritten by the gateway with a 301; the
    /// canonical (bare digits) form goes straight through.
    func testImdbIdIsSentInItsCanonicalForm() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(searchJSON.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        _ = try await client.search(OpenSubtitlesClient.SearchQuery(
            title: "The Movie",
            imdbId: "tt0111161"
        ))

        let request = try XCTUnwrap(session.capturedRequests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["imdb_id"], "111161")
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

    func testDownloadFollowsTheLinkAndUnzipsTheFile() async throws {
        let linkJSON = """
        { "link": "https://dl.opensubtitles.com/file.srt.gz", "file_name": "The.Movie.spa.srt", "remaining": 99 }
        """
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(linkJSON.utf8), statusCode: 200),
            .init(data: Data(Self.gzipFixture), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        let file = try await client.download(subtitleId: "5512345", fileId: 987)

        XCTAssertEqual(file.text, Self.plainFixture)
        XCTAssertEqual(file.format, "srt")
        XCTAssertEqual(file.fileName, "The.Movie.spa.srt")

        XCTAssertEqual(session.capturedRequests.count, 2)
        let first = try XCTUnwrap(session.capturedRequests[0].url)
        XCTAssertEqual(first.path, "/api/v1/subtitles/5512345/download")
        let second = try XCTUnwrap(session.capturedRequests[1].url)
        XCTAssertEqual(second.absoluteString, "https://dl.opensubtitles.com/file.srt.gz")
    }

    func testDownloadAcceptsAPlainFileToo() async throws {
        let linkJSON = """
        { "link": "https://dl.opensubtitles.com/file.srt", "file_name": "The.Movie.spa.srt" }
        """
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(linkJSON.utf8), statusCode: 200),
            .init(data: Data(Self.plainFixture.utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        let file = try await client.download(subtitleId: "1", fileId: nil)
        XCTAssertEqual(file.text, Self.plainFixture)
    }

    func testDownloadWithoutALinkIsRejected() async {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data("{}".utf8), statusCode: 200)
        ])
        let client = OpenSubtitlesClient(apiKey: "k", session: session, baseURL: baseURL)

        do {
            _ = try await client.download(subtitleId: "1", fileId: nil)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? OpenSubtitlesError, .malformedResponse)
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
