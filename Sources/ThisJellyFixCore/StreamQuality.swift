import Foundation

/// Playback quality cap offered in the player's quality picker.
///
/// Jellyfin caps quality through `MaxStreamingBitrate` in the PlaybackInfo
/// request: below the source's bitrate the server answers with a transcoded
/// HLS ladder limited to that ceiling. `.auto` sends no cap, so the server
/// keeps whatever it would have chosen anyway (direct play / remux).
public enum StreamQuality: Int, CaseIterable, Identifiable, Sendable {
    case auto = 0
    case q1080 = 1
    case q720 = 2
    case q480 = 3
    case q360 = 4

    public var id: Int { rawValue }

    /// Short label shown in the picker row.
    public var label: String {
        switch self {
        case .auto: return "Automático"
        case .q1080: return "1080p"
        case .q720: return "720p"
        case .q480: return "480p"
        case .q360: return "360p"
        }
    }

    /// Bitrate ceiling in bits/s; nil = no cap (server decides).
    public var maxBitrate: Int? {
        switch self {
        case .auto: return nil
        case .q1080: return 12_000_000
        case .q720: return 8_000_000
        case .q480: return 4_000_000
        case .q360: return 2_000_000
        }
    }
}
