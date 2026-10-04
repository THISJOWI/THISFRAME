import Foundation

/// Everything a Handoff continuation must carry to restart content on the
/// receiving device. Token deliberately absent — the receiver reads its own
/// from the shared Keychain.
public struct HandoffIntent: Sendable, Equatable {
    public let itemId: String
    public let serverURL: URL
    public let title: String
    public let mediaType: String
    /// Playback position in seconds at publish time; nil for "detail" intents.
    public let position: Double?
    /// When the continuation was received — expiry stops an intent that was
    /// never resolvable (failed/empty library) from autoplaying hours later.
    public let receivedAt: Date

    public init(
        itemId: String,
        serverURL: URL,
        title: String,
        mediaType: String,
        position: Double?,
        receivedAt: Date = Date()
    ) {
        self.itemId = itemId
        self.serverURL = serverURL
        self.title = title
        self.mediaType = mediaType
        self.position = position
        self.receivedAt = receivedAt
    }
}

/// Whether the library the intent will be resolved against is usable yet.
public enum HandoffLibraryState: Sendable, Equatable {
    /// A LibraryModel exists but `load()` has not finished — `rows` may be
    /// empty or partial, so a lookup against it is meaningless.
    case notLoaded
    case loaded(itemCount: Int)
}

/// Outcome of resolving a pending Handoff intent.
public enum HandoffResolution: Sendable, Equatable {
    /// No pending intent — nothing to do.
    case idle
    /// Library not ready: KEEP the intent (do not consume) and try again
    /// when loading finishes. This is the cold-launch Dock fix: the old code
    /// consumed the payload against an empty library and navigated nowhere.
    case keepWaiting(String)
    /// Library ready and the item is present — navigate (consume intent).
    case navigate
    /// Library ready but the item is genuinely absent — consume and log.
    case notFound
    /// The intent outlived its usefulness (never resolvable within the
    /// window) — consume and log instead of autoplaying stale content.
    case expired
}

/// Pure decision logic for Handoff continuations (unit-tested).
public enum HandoffResolver {
    /// How long a not-yet-resolvable intent stays alive. Long enough for a
    /// cold launch + slow library load; short enough that a later unrelated
    /// successful load doesn't replay it.
    public static let intentLifetime: TimeInterval = 300

    public static func resolve(
        intent: HandoffIntent?,
        library: HandoffLibraryState,
        itemExists: Bool,
        now: Date = Date()
    ) -> HandoffResolution {
        guard let intent else { return .idle }
        guard now.timeIntervalSince(intent.receivedAt) <= intentLifetime else {
            return .expired
        }
        switch library {
        case .notLoaded:
            return .keepWaiting("library not loaded")
        case .loaded:
            return itemExists ? .navigate : .notFound
        }
    }

    /// Where playback should start after a Handoff continuation: the furthest
    /// of the publisher's position and the server's saved resume point (the
    /// server may be ahead if the sender kept reporting, behind if it died).
    public static func effectiveStart(handoff: Double?, serverResume: Double?) -> Double {
        max(handoff ?? 0, serverResume ?? 0)
    }
}
