import Foundation
import ThisJellyFixCore

public protocol JellyfinPlaybackProviding: Sendable {
    func fetchPlaybackInfo(userId: String, serverURL: URL, token: String, itemId: String) async throws -> PlaybackInfo
}

public struct JellyfinPlaybackClient: JellyfinPlaybackProviding {
    private let session: any JellyfinNetworkSession

    public init(session: any JellyfinNetworkSession = URLSession.shared) {
        self.session = session
    }

    public func fetchPlaybackInfo(userId: String, serverURL: URL, token: String, itemId: String) async throws -> PlaybackInfo {
        try await fetchPlaybackInfo(userId: userId, serverURL: serverURL, token: token, itemId: itemId, deviceProfile: nil)
    }

    /// Same as `fetchPlaybackInfo` but sends a Jellyfin DeviceProfile so the
    /// server answers with a specific playback plan (e.g. an HLS-only profile
    /// yields a `TranscodingUrl` usable by AVPlayer picture-in-picture).
    ///
    /// `maxStreamingBitrate` caps the answer in bits/s (quality picker): the
    /// server then returns a transcoded HLS variant limited to that ceiling
    /// instead of the original file. nil = no cap.
    ///
    /// `subtitleStreamIndex` defaults to -1: the server selects/burns NO
    /// subtitle stream into the video. The client overlay is the single
    /// subtitle renderer (black background box); without this the server
    /// applies the user's profile default and the transcoded video carries a
    /// second, background-less copy of the same lines.
    /// `alwaysBurnInSubtitleWhenTranscoding` defaults to false for the same
    /// reason: nothing may be pixel-burned into the frames. nil opts out of
    /// a key entirely (lets the server decide).
    ///
    /// `audioStreamIndex` selects WHICH audio the server serves in a
    /// remux/transcode (single-audio output): nil = server default (usually
    /// the first/default track, which is why alternate audios "disappear").
    public func fetchPlaybackInfo(
        userId: String,
        serverURL: URL,
        token: String,
        itemId: String,
        deviceProfile: PlaybackDeviceProfile?,
        maxStreamingBitrate: Int? = nil,
        subtitleStreamIndex: Int? = -1,
        alwaysBurnInSubtitleWhenTranscoding: Bool? = false,
        audioStreamIndex: Int? = nil
    ) async throws -> PlaybackInfo {
        let url = serverURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "MediaBrowser Client=\"thisjellyfix\", Device=\"\(deviceOS)\", DeviceId=\"\(DeviceIdentifier().current())\", Version=\"0.1\", Token=\"\(token)\"",
            forHTTPHeaderField: "Authorization"
        )

        var body: [String: Any] = [
            "UserId": userId,
            "DeviceId": DeviceIdentifier().current(),
            "MediaSourceId": itemId,
        ]
        if let subtitleStreamIndex {
            // -1 explicitly tells Jellyfin not to select/burn any subtitle stream into the video
            body["SubtitleStreamIndex"] = subtitleStreamIndex
        }
        if let audioStreamIndex {
            // A remux/transcode carries a SINGLE audio: without this the
            // server serves its default and the other tracks never reach us.
            body["AudioStreamIndex"] = audioStreamIndex
        }
        if let alwaysBurnInSubtitleWhenTranscoding {
            body["AlwaysBurnInSubtitleWhenTranscoding"] = alwaysBurnInSubtitleWhenTranscoding
        }
        if let deviceProfile {
            let profileData = try JSONEncoder().encode(deviceProfile)
            body["DeviceProfile"] = try JSONSerialization.jsonObject(with: profileData)
        }
        if let maxStreamingBitrate {
            body["MaxStreamingBitrate"] = maxStreamingBitrate
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryError.invalidResponse
        }

        // Diagnostic line through TJFLog: redacts `api_key`/`AccessToken`
        // (raw body used to be appended to a file that grew forever) and
        // truncates so a big DeviceProfile answer can't flood the log.
        TJFLog("[PlaybackClient] status=\(httpResponse.statusCode) body=\(Self.truncated(String(data: data, encoding: .utf8) ?? "", limit: 800))")

        switch httpResponse.statusCode {
        case 200: break
        case 401: throw LibraryError.unauthorized
        default: throw LibraryError.serverError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(PlaybackInfo.self, from: data)
        TJFLog("[PlaybackClient] decoded mediaSources=\(decoded.mediaSources.count)")
        return decoded
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…(\(text.count) chars)" : text
    }

    private var deviceOS: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(visionOS)
        "visionOS"
        #else
        "unknown"
        #endif
    }
}

// MARK: - Active Sessions (handoff takeover)

/// Minimal view of a Jellyfin `/Sessions` entry — only what the handoff
/// takeover check needs (who is playing what, right now).
public struct ActiveSessionInfo: Decodable, Sendable, Equatable {
    public let deviceId: String?
    public let userId: String?
    public let deviceName: String?
    public let nowPlayingItemId: String?
    public let isPaused: Bool

    public init(
        deviceId: String?,
        userId: String?,
        deviceName: String?,
        nowPlayingItemId: String?,
        isPaused: Bool
    ) {
        self.deviceId = deviceId
        self.userId = userId
        self.deviceName = deviceName
        self.nowPlayingItemId = nowPlayingItemId
        self.isPaused = isPaused
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "DeviceId"
        case userId = "UserId"
        case deviceName = "DeviceName"
        case nowPlayingItem = "NowPlayingItem"
        case playState = "PlayState"
        case itemId = "Id"
        case isPaused = "IsPaused"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        // NowPlayingItem is a nested object ({"Id": ...}) — nil when idle.
        if let item = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .nowPlayingItem) {
            nowPlayingItemId = try item.decodeIfPresent(String.self, forKey: .itemId)
        } else {
            nowPlayingItemId = nil
        }
        if let state = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .playState) {
            isPaused = (try? state.decodeIfPresent(Bool.self, forKey: .isPaused)) ?? false
        } else {
            isPaused = false
        }
    }

    /// The OTHER session that has taken playback of `itemId` away from this
    /// device, if any: a different DeviceId actively playing the same item
    /// (paused peers haven't taken over — they may resume on our device).
    public static func takeoverSource(
        in sessions: [ActiveSessionInfo],
        ourDeviceId: String,
        itemId: String
    ) -> ActiveSessionInfo? {
        sessions.first { session in
            session.deviceId != nil
                && session.deviceId != ourDeviceId
                && session.nowPlayingItemId == itemId
                && session.isPaused == false
        }
    }
}

public protocol JellyfinSessionProviding: Sendable {
    func fetchActiveSessions(serverURL: URL, token: String) async throws -> [ActiveSessionInfo]
}

/// GET /Sessions: every active session on the server. Used to detect that a
/// handoff moved playback to another device (NSUserActivity is one-way — the
/// only cross-device signal available after the continuation is delivered).
public struct JellyfinSessionClient: JellyfinSessionProviding {
    private let session: any JellyfinNetworkSession

    public init(session: any JellyfinNetworkSession = URLSession.shared) {
        self.session = session
    }

    public func fetchActiveSessions(serverURL: URL, token: String) async throws -> [ActiveSessionInfo] {
        let url = serverURL.appendingPathComponent("Sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(
            "MediaBrowser Client=\"thisjellyfix\", Device=\"\(deviceOS)\", DeviceId=\"\(DeviceIdentifier().current())\", Version=\"0.1\", Token=\"\(token)\"",
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200: break
        case 401: throw LibraryError.unauthorized
        default: throw LibraryError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode([ActiveSessionInfo].self, from: data)
    }

    private var deviceOS: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(visionOS)
        "visionOS"
        #else
        "unknown"
        #endif
    }
}

// MARK: - Playback Reporting

/// Reports playback progress to Jellyfin so episodes get marked as watched.
/// Jellyfin considers an item "watched" when progress >= 90%.
public struct JellyfinPlaybackReporter: Sendable {
    private let session: any JellyfinNetworkSession

    /// Server-issued PlaySessionId from PlaybackInfo — echoed on every report
    /// so Jellyfin attributes progress to the right playback session.
    public var playSessionId: String? = nil

    public init(session: any JellyfinNetworkSession = URLSession.shared) {
        self.session = session
    }

    private func authHeader(token: String) -> String {
        "MediaBrowser Client=\"thisjellyfix\", Device=\"\(deviceOS)\", DeviceId=\"\(DeviceIdentifier().current())\", Version=\"0.1\", Token=\"\(token)\""
    }

    private var deviceOS: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(visionOS)
        "visionOS"
        #else
        "unknown"
        #endif
    }

    /// Report that playback has started.
    public func reportPlaying(
        userId: String,
        serverURL: URL,
        token: String,
        itemId: String,
        mediaSourceId: String
    ) async {
        await report(
            endpoint: "Sessions/Playing",
            userId: userId,
            serverURL: serverURL,
            token: token,
            itemId: itemId,
            mediaSourceId: mediaSourceId
        )
    }

    /// Report playback progress (call periodically).
    public func reportProgress(
        userId: String,
        serverURL: URL,
        token: String,
        itemId: String,
        mediaSourceId: String,
        positionTicks: Int64,
        isPaused: Bool
    ) async {
        // PositionTicks:0 is AUTHORITATIVE for Jellyfin: the server stores it
        // and the item stops being resumable (the resume row drops it). No
        // caller has a legitimate reason to send it — a handoff that captured
        // position 0 (seek not landed yet) must not erase the saved progress,
        // so this is the single choke point that protects every path.
        guard positionTicks > 0 else {
            TJFLog("reportProgress SKIPPED positionTicks<=0 item=\(itemId) (preserves saved resume)")
            return
        }
        let body: [String: Any] = [
            "ItemId": itemId,
            "MediaSourceId": mediaSourceId,
            "PositionTicks": positionTicks,
            "IsPaused": isPaused,
            "IsMuted": false,
        ]
        await report(
            endpoint: "Sessions/Playing/Progress",
            userId: userId,
            serverURL: serverURL,
            token: token,
            body: body
        )
    }

    /// Report that playback has stopped.
    public func reportStopped(
        userId: String,
        serverURL: URL,
        token: String,
        itemId: String,
        mediaSourceId: String,
        positionTicks: Int64
    ) async {
        // Same rule as progress — a stop at 0 wipes the resume entry.
        guard positionTicks > 0 else {
            TJFLog("reportStopped SKIPPED positionTicks<=0 item=\(itemId) (preserves saved resume)")
            return
        }
        let body: [String: Any] = [
            "ItemId": itemId,
            "MediaSourceId": mediaSourceId,
            "PositionTicks": positionTicks,
        ]
        await report(
            endpoint: "Sessions/Playing/Stopped",
            userId: userId,
            serverURL: serverURL,
            token: token,
            body: body
        )
    }

    private func report(
        endpoint: String,
        userId: String,
        serverURL: URL,
        token: String,
        itemId: String,
        mediaSourceId: String
    ) async {
        let body: [String: Any] = [
            "ItemId": itemId,
            "MediaSourceId": mediaSourceId,
        ]
        await report(
            endpoint: endpoint,
            userId: userId,
            serverURL: serverURL,
            token: token,
            body: body
        )
    }

    private func report(
        endpoint: String,
        userId: String,
        serverURL: URL,
        token: String,
        body: [String: Any]
    ) async {
        let url = serverURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader(token: token), forHTTPHeaderField: "Authorization")
        var finalBody = body
        if let playSessionId {
            finalBody["PlaySessionId"] = playSessionId
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: finalBody)

        let logBody: String
        if let data = request.httpBody, let str = String(data: data, encoding: .utf8) {
            logBody = str
        } else {
            logBody = "nil"
        }
        TJFLog("HTTP → \(endpoint) url=\(url.absoluteString) body=\(logBody)")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                let responseStr = String(data: data, encoding: .utf8) ?? "binary"
                TJFLog("HTTP ← \(endpoint) status=\(http.statusCode) response=\(responseStr.prefix(300))")
            }
        } catch {
            TJFLog("HTTP ← \(endpoint) ERROR: \(error.localizedDescription)")
        }
    }
}
