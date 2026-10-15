import Foundation

/// Represents an audio track available in the current media.
public struct AudioTrack: Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    /// Raw ISO-639 code as reported by the engine — used for language
    /// preference matching. Never display this directly.
    public let language: String?
    /// Human-readable language for display (e.g. "Inglés"), derived by
    /// `TrackNaming` from server/engine metadata.
    public let languageName: String?

    public init(id: Int, name: String, language: String? = nil, languageName: String? = nil) {
        self.id = id
        self.name = name
        self.language = language
        self.languageName = languageName
    }
}

/// Represents a subtitle track available in the current media.
public struct SubtitleTrack: Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    /// Raw ISO-639 code as reported by the engine — used for language
    /// preference matching. Never display this directly.
    public let language: String?
    /// Human-readable language for display (e.g. "Inglés"), derived by
    /// `TrackNaming` from server/engine metadata.
    public let languageName: String?
    public let isExternal: Bool
    /// Server metadata (overlay tracks only; native options report false).
    /// Used ONLY to order the automatic pick and to label rows
    /// ("Forzados"/"SDH") — never to hide a track.
    public let isForced: Bool
    public let isHearingImpaired: Bool
    public let isDefault: Bool

    public init(
        id: Int,
        name: String,
        language: String? = nil,
        languageName: String? = nil,
        isExternal: Bool = false,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.languageName = languageName
        self.isExternal = isExternal
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isDefault = isDefault
    }
}
