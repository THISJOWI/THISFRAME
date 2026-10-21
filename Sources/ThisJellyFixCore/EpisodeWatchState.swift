import Foundation

/// Playback state of a single episode, as the server reports it.
///
/// The server is the only authority: an episode is "watched" **only** when
/// Jellyfin says `Played`. A playback position alone never means "watched" —
/// it means "in progress". Nothing here is inferred from local state.
public enum EpisodeWatchState: Sendable, Equatable {
    /// Never started, or no progress recorded at all.
    case unwatched
    /// Started but not finished. `fraction` is the played share of the
    /// episode in `0...1`, or `nil` when the duration is unknown.
    case inProgress(fraction: Double?)
    /// Marked as played by the server.
    case watched
}

public extension JellyfinEpisode {

    /// The episode's playback state.
    ///
    /// Precedence — the server's explicit `Played` flag always wins:
    /// 1. `played == true` → `.watched` (a residual position is not progress).
    /// 2. a position or a percentage above zero → `.inProgress`.
    /// 3. otherwise → `.unwatched`.
    var watchState: EpisodeWatchState {
        // 1. Explicitly played — the server says so, nothing overrides it.
        if isPlayed { return .watched }

        let position = resumePositionSeconds ?? 0
        let percentage = playedPercentage ?? 0
        // 2. "Started" means a real position or a real percentage. A zero
        //    position is NOT progress — the player never reports 0 either
        //    (see `JellyfinPlaybackReporter.reportProgress`).
        guard position > 0 || percentage > 0 else { return .unwatched }

        // 3. Prefer the server's own percentage; fall back to position ÷
        //    duration. Without a duration the share is unknown — the UI
        //    shows minutes watched instead of a bar.
        let fraction: Double?
        if percentage > 0 {
            fraction = percentage / 100.0
        } else if let duration = durationSeconds, duration > 0 {
            fraction = position / duration
        } else {
            fraction = nil
        }
        return .inProgress(fraction: fraction.map { min(max($0, 0), 1) })
    }
}
