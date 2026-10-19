import Foundation
import ThisJellyFixCore

/// Errors reported by the OpenSubtitles.com API.
public enum OpenSubtitlesError: LocalizedError, Equatable {
    case missingCredentials
    case missingQuery
    case missingFile
    case invalidAPIKey
    case rateLimited
    case notFound
    case serverError(Int)
    case malformedResponse
    case emptyFile
    case compressedPayloadUnreadable

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Falta la API key de OpenSubtitles."
        case .missingQuery:
            "No hay datos suficientes para buscar subtítulos de este contenido."
        case .missingFile:
            "Ese subtítulo no expone un fichero descargable."
        case .invalidAPIKey:
            "OpenSubtitles rechazó la API key. Compruébala en opensubtitles.com."
        case .rateLimited:
            "OpenSubtitles ha limitado las peticiones. Espera un momento y vuelve a intentarlo."
        case .notFound:
            "Ese subtítulo ya no está disponible en OpenSubtitles."
        case .serverError(let code):
            "OpenSubtitles respondió con un error (HTTP \(code))."
        case .malformedResponse:
            "OpenSubtitles devolvió una respuesta que no se pudo leer."
        case .emptyFile:
            "El archivo de subtítulo llegó vacío."
        case .compressedPayloadUnreadable:
            "El archivo de subtítulo llegó comprimido y no se pudo descomprimir."
        }
    }
}

/// Client for the OpenSubtitles.com REST API (v1), used by the providers the
/// app queries itself.
///
/// The contract was taken from OpenSubtitles' own reference client
/// (`opensubtitles/mcp.opensubtitles.com`), not guessed:
/// - `GET /api/v1/subtitles` → `{ "data": [ { "id", "type", "attributes": {…} } ] }`
///   The interesting fields live under `attributes`; the flat shape is still
///   accepted as a fallback.
/// - `POST /api/v1/download?file_id={id}` → `{ "link": "https://dl.opensubtitles.com/…" }`
/// - that link returns the subtitle file, usually gzip-compressed.
///
/// The provider's gateway answers 301 when the query string is not
/// canonical, so the parameters are sent sorted, lowercased and with the
/// ids normalised (no `tt` prefix, no leading zeroes).
///
/// Two headers are mandatory: `Api-Key` (the user's key) and `User-Agent`
/// (the API blocks anonymous agents). Nothing about the key is ever
/// logged — only the status codes are.
public struct OpenSubtitlesClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.opensubtitles.com")!

    /// Identifies the app to the API. The API requires a `User-Agent` and
    /// blocks the generic ones.
    public static let userAgent = "ThisJellyFix v1.0 (+https://github.com/THISJOWI/THISJELLYFIX)"

    /// Title used by the "probar conexión" button. A real, stable search
    /// proves the key works instead of just pinging the host.
    static let connectionProbeTitle = "matrix"

    private let apiKey: String
    private let session: any JellyfinNetworkSession
    private let baseURL: URL

    public init(
        apiKey: String,
        session: any JellyfinNetworkSession = URLSession.shared,
        baseURL: URL = OpenSubtitlesClient.defaultBaseURL
    ) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: - Query

    /// What to look for. The more precise the fields, the better the match.
    ///
    /// The provider distinguishes a *movie* id (`imdb_id`/`tmdb_id`) from the
    /// *series* an episode belongs to (`parent_imdb_id`/`parent_tmdb_id`):
    /// an episode is searched with the parent's id plus its season and
    /// episode number.
    public struct SearchQuery: Sendable, Equatable {
        public var title: String?
        /// IMDb id of the movie (`tt0111161`).
        public var imdbId: String?
        /// TMDB id of the movie.
        public var tmdbId: String?
        /// IMDb id of the series an episode belongs to.
        public var parentImdbId: String?
        /// TMDB id of the series an episode belongs to.
        public var parentTmdbId: String?
        public var seasonNumber: Int?
        public var episodeNumber: Int?
        /// ISO 639-1 code (`es`, `en`). nil = any language.
        public var language: String?

        public init(
            title: String? = nil,
            imdbId: String? = nil,
            tmdbId: String? = nil,
            parentImdbId: String? = nil,
            parentTmdbId: String? = nil,
            seasonNumber: Int? = nil,
            episodeNumber: Int? = nil,
            language: String? = nil
        ) {
            self.title = title
            self.imdbId = imdbId
            self.tmdbId = tmdbId
            self.parentImdbId = parentImdbId
            self.parentTmdbId = parentTmdbId
            self.seasonNumber = seasonNumber
            self.episodeNumber = episodeNumber
            self.language = language
        }
    }

    /// One subtitle the provider offers.
    public struct Result: Sendable, Equatable {
        public let subtitleId: String
        /// Id of the file to download. A subtitle can bundle several files
        /// (a season pack); this is the one to ask for.
        public let fileId: Int?
        public let fileName: String?
        public let release: String?
        /// ISO 639-1 code of the subtitle language.
        public let languageCode: String?
        public let downloadCount: Int?
        public let rating: Float?
        public let hearingImpaired: Bool
        public let forced: Bool
        public let machineTranslated: Bool
    }

    /// The downloaded file, ready to be handed to the server.
    public struct File: Sendable, Equatable {
        /// The subtitle text.
        public let text: String
        /// Format the server should store it as (`srt`, `vtt`, `ass`…).
        public let format: String
        /// Original file name, kept for the log.
        public let fileName: String?
    }

    // MARK: - Search

    /// Search the provider.
    public func search(_ query: SearchQuery) async throws -> [Result] {
        var items: [URLQueryItem] = []
        if let title = query.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            items.append(URLQueryItem(name: "query", value: title))
        }
        if let imdbId = query.imdbId.flatMap(Self.canonicalImdbId) {
            items.append(URLQueryItem(name: "imdb_id", value: imdbId))
        }
        if let tmdbId = query.tmdbId.flatMap(Self.canonicalNumericId) {
            items.append(URLQueryItem(name: "tmdb_id", value: tmdbId))
        }
        if let parentImdbId = query.parentImdbId.flatMap(Self.canonicalImdbId) {
            items.append(URLQueryItem(name: "parent_imdb_id", value: parentImdbId))
        }
        if let parentTmdbId = query.parentTmdbId.flatMap(Self.canonicalNumericId) {
            items.append(URLQueryItem(name: "parent_tmdb_id", value: parentTmdbId))
        }
        if let season = query.seasonNumber {
            items.append(URLQueryItem(name: "season_number", value: String(season)))
        }
        if let episode = query.episodeNumber {
            items.append(URLQueryItem(name: "episode_number", value: String(episode)))
        }
        if let language = query.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            items.append(URLQueryItem(name: "languages", value: language))
        }
        guard !items.isEmpty else { throw OpenSubtitlesError.missingQuery }

        // The gateway canonicalises the query string and answers with a 301
        // when the parameters are not sorted alphabetically. It also expects
        // lower-case values. Sending the canonical form straight away avoids
        // the redirect — which also keeps the API key on a single request.
        items.sort { $0.name < $1.name }
        let canonical = items.map { URLQueryItem(name: $0.name, value: $0.value?.lowercased()) }

        let url = baseURL
            .appendingPathComponent("api/v1/subtitles")
            .appending(queryItems: canonical)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        applyHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let payload = try decodeJSON(SearchResponse.self, from: data)
        let results = (payload.data ?? []).map { $0.result }
        TJFLog("opensubtitles: search results=\(results.count)")
        return results
    }

    /// Cheap, real check that the key is accepted: one search against a
    /// well-known title. Returns how many subtitles the provider returned.
    public func testConnection() async throws -> Int {
        let results = try await search(SearchQuery(
            title: Self.connectionProbeTitle,
            language: "en"
        ))
        return results.count
    }

    // MARK: - Download

    /// Download a subtitle file.
    ///
    /// - Parameter fileId: the `file_id` the search returned. It is what
    ///   identifies the concrete file to download (a subtitle can bundle
    ///   several).
    public func download(fileId: Int) async throws -> File {
        let url = baseURL
            .appendingPathComponent("api/v1/download")
            .appending(queryItems: [URLQueryItem(name: "file_id", value: String(fileId))])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        // No body: the provider expects the file id in the query string.
        applyHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let payload = try decodeJSON(DownloadResponse.self, from: data)
        guard let link = payload.link, !link.isEmpty else {
            throw OpenSubtitlesError.malformedResponse
        }
        guard let fileURL = URL(string: link) else {
            throw OpenSubtitlesError.malformedResponse
        }

        var fileRequest = URLRequest(url: fileURL)
        fileRequest.httpMethod = "GET"
        fileRequest.timeoutInterval = 60
        // The link is pre-signed: the API key is NOT sent to the CDN.
        fileRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (fileData, fileResponse) = try await session.data(for: fileRequest)
        try validate(response: fileResponse, data: fileData)

        // The file arrives gzipped. A payload that claims to be gzip but
        // cannot be inflated is broken — it must NOT reach the server.
        let raw: Data
        if Gzip.isGzipped(fileData) {
            guard let inflated = Gzip.inflate(fileData) else {
                throw OpenSubtitlesError.compressedPayloadUnreadable
            }
            raw = inflated
        } else {
            raw = fileData
        }
        guard !raw.isEmpty else { throw OpenSubtitlesError.emptyFile }
        guard let text = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) else {
            throw OpenSubtitlesError.malformedResponse
        }
        let fileName = payload.fileName
        let format = Self.format(fromFileName: fileName)
        TJFLog("opensubtitles: downloaded fileId=\(fileId) format=\(format) bytes=\(raw.count)")
        return File(text: text, format: format, fileName: fileName)
    }

    // MARK: - Helpers

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    }

    /// Map the HTTP status to a precise error. The API answers 401/403 for a
    /// rejected key and 429 when the anonymous quota is exhausted.
    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenSubtitlesError.malformedResponse
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw OpenSubtitlesError.invalidAPIKey
        case 404:
            throw OpenSubtitlesError.notFound
        case 429:
            throw OpenSubtitlesError.rateLimited
        default:
            throw OpenSubtitlesError.serverError(http.statusCode)
        }
    }

    /// Decode JSON, transparently handling the gzip-compressed body the API
    /// sometimes answers with.
    private func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let decoded = try? JSONDecoder().decode(type, from: data) {
            return decoded
        }
        guard let inflated = Gzip.inflate(data) else {
            throw OpenSubtitlesError.malformedResponse
        }
        guard let decoded = try? JSONDecoder().decode(type, from: inflated) else {
            throw OpenSubtitlesError.malformedResponse
        }
        return decoded
    }

    /// The provider's canonical form of an IMDb id: the bare digits, with
    /// the `tt` prefix and the zero padding removed.
    ///
    /// The zero-padded form (`tt0111161`) makes the gateway answer with a
    /// 301 that rewrites the value; the canonical form goes straight
    /// through. nil when the id is not a number.
    public static func canonicalImdbId(_ raw: String) -> String? {
        var digits = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if digits.hasPrefix("tt") { digits.removeFirst(2) }
        digits = digits.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        return canonicalNumericId(digits)
    }

    /// The canonical form of a numeric id: the digits without the leading
    /// zeroes. nil when the value is not a number.
    public static func canonicalNumericId(_ raw: String) -> String? {
        var digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        // The gateway drops the zero padding too.
        while digits.count > 1, digits.hasPrefix("0") { digits.removeFirst() }
        return digits
    }

    /// Subtitle format from the file name the provider reports.
    public static func format(fromFileName fileName: String?) -> String {
        guard let fileName else { return "srt" }
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "srt": return "srt"
        case "vtt": return "vtt"
        case "ass", "ssa": return "ass"
        case "sub": return "sub"
        case "smi": return "smi"
        case "sbv": return "sbv"
        case "txt": return "txt"
        default: return "srt"
        }
    }
}

// MARK: - Player result

public extension SubtitleSearchResult {
    /// Adapt an OpenSubtitles result to the unified row the player's search
    /// sheet shows.
    init(openSubtitles result: OpenSubtitlesClient.Result, provider: SubtitleProviderID) {
        let title = result.release ?? result.fileName ?? "Subtítulo"
        self.init(
            id: "opensubtitles:\(result.subtitleId)",
            providerName: "OpenSubtitles",
            name: title,
            format: OpenSubtitlesClient.format(fromFileName: result.fileName),
            languageCode: result.languageCode,
            downloadCount: result.downloadCount,
            communityRating: result.rating,
            isHashMatch: false,
            isMachineTranslated: result.machineTranslated,
            isForced: result.forced,
            isHearingImpaired: result.hearingImpaired,
            handle: .clientSide(
                provider: provider,
                subtitleId: result.subtitleId,
                fileId: result.fileId
            )
        )
    }
}

// MARK: - Wire format

/// One search hit. The provider nests the interesting fields under
/// `attributes`; the flat shape is still accepted as a fallback.
private struct SearchResponse: Decodable {
    struct Attributes: Decodable {
        struct File: Decodable {
            let fileId: FlexibleValue?
            let fileName: String?

            enum CodingKeys: String, CodingKey {
                case fileId = "file_id"
                case fileName = "file_name"
            }
        }

        let subtitleId: FlexibleValue?
        let language: String?
        let downloadCount: Int?
        let hearingImpaired: Bool?
        let forced: Bool?
        let aiTranslated: Bool?
        let machineTranslated: Bool?
        let release: String?
        let ratings: Float?
        let files: [File]?

        enum CodingKeys: String, CodingKey {
            case subtitleId = "subtitle_id"
            case language
            case downloadCount = "download_count"
            case hearingImpaired = "hearing_impaired"
            case forced
            case aiTranslated = "ai_translated"
            case machineTranslated = "machine_translated"
            case release
            case ratings
            case files
        }
    }

    struct Item: Decodable {
        let id: FlexibleValue
        let type: String?
        let attributes: Attributes?

        // Flat (older) shape, kept as a fallback.
        let language: String?
        let languageCode: String?
        let release: String?
        let downloadCount: Int?
        let rating: Float?
        let hearingImpaired: Bool?
        let forced: Bool?
        let aiTranslated: Bool?
        let files: [Attributes.File]?

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case attributes
            case language
            case languageCode = "language_code"
            case release
            case downloadCount = "download_count"
            case rating
            case hearingImpaired = "hearing_impaired"
            case forced
            case aiTranslated = "ai_translated"
            case files
        }

        var result: OpenSubtitlesClient.Result {
            let attributes = self.attributes
            let file = (attributes?.files ?? files ?? []).first
            return OpenSubtitlesClient.Result(
                subtitleId: attributes?.subtitleId?.stringValue ?? id.stringValue,
                fileId: file?.fileId?.intValue,
                fileName: file?.fileName,
                release: attributes?.release ?? release,
                languageCode: attributes?.language ?? languageCode ?? language,
                downloadCount: attributes?.downloadCount ?? downloadCount,
                rating: attributes?.ratings ?? rating,
                hearingImpaired: attributes?.hearingImpaired ?? hearingImpaired ?? false,
                forced: attributes?.forced ?? forced ?? false,
                machineTranslated: attributes?.machineTranslated
                    ?? attributes?.aiTranslated
                    ?? aiTranslated
                    ?? false
            )
        }
    }

    let totalCount: Int?
    let data: [Item]?

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case data
    }
}

private struct DownloadResponse: Decodable {
    let link: String?
    let fileName: String?
    let remaining: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case link
        case fileName = "file_name"
        case remaining
        case message
    }
}

/// A JSON value that may arrive as a string or as a number.
///
/// The API is not consistent here (`"id": "123"` in one place, a bare
/// number in another), and a decode failure would silently drop every
/// result — so both shapes are accepted.
private struct FlexibleValue: Decodable {
    let stringValue: String
    let intValue: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            stringValue = string
            intValue = Int(string)
        } else if let int = try? container.decode(Int.self) {
            stringValue = String(int)
            intValue = int
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a string or a number"
            )
        }
    }
}
