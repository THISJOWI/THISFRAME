import Foundation

/// AirPlay connection lifecycle for the playback engine.
///
/// Pure state machine (unit-tested): the engine feeds it system events
/// (route selection, `isExternalPlaybackActive`, timeouts, item swaps) and
/// the UI reads `blocksTransportCommands` so play/pause cannot abort a
/// handoff that is still negotiating — the race behind "the change starts
/// but never completes" and "the source keeps playing".
public struct AirPlayRouteState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// No receiver engaged — normal local playback.
        case idle
        /// A route was picked (or the system started a handoff) but external
        /// playback has not engaged yet. Transport commands are blocked.
        case connecting(routeName: String)
        /// External playback is live on the receiver.
        case active
        /// The connection attempt failed; the source stays local.
        case failed(reason: String)
    }

    public private(set) var phase: Phase = .idle

    /// Last route we started connecting to (nil until first selection).
    public private(set) var selectedRouteName: String?

    public init() {}

    public var isConnecting: Bool {
        if case .connecting = phase { return true }
        return false
    }

    /// While a handoff is negotiating, transport commands must be ignored:
    /// a play/pause in that window aborts the connection in AVPlayer.
    public var blocksTransportCommands: Bool { isConnecting }

    // MARK: Events

    /// User (or system) picked a receiver → connection attempt starts.
    public mutating func routeSelected(name: String) {
        selectedRouteName = name
        phase = .connecting(routeName: name)
    }

    /// `AVPlayer.isExternalPlaybackActive` KVO — the ground truth.
    public mutating func externalPlaybackChanged(_ active: Bool) {
        if active {
            phase = .active
        }
        // false while connecting is the NORMAL pre-state — keep waiting;
        // an active→false transition is handled by noteRouteLost().
    }

    /// 10 s without `isExternalPlaybackActive` after selection.
    public mutating func timedOut() {
        guard case .connecting(let name) = phase else { return }
        phase = .failed(reason: "\(name) no respondió en 10 s")
    }

    /// Explicit failure reported by the system/engine.
    public mutating func failed(reason: String) {
        guard case .connecting = phase else { return }
        phase = .failed(reason: reason)
    }

    /// `replaceCurrentItem` ran while connecting (episode swap, new prepare):
    /// the pending handoff is dead — say so instead of silently reverting.
    public mutating func noteItemReplaced() {
        guard case .connecting = phase else { return }
        phase = .failed(reason: "cambio de contenido durante la conexión")
    }

    /// External playback dropped while it was live (receiver gone/off).
    public mutating func noteRouteLost() {
        guard case .active = phase else { return }
        phase = .idle
        selectedRouteName = nil
    }

    /// Receiver deselected while still negotiating (picker dismissed, route
    /// changed back to local): back to idle, NOT failed — nothing broke, the
    /// user simply changed their mind. Without this the machine sat in
    /// `connecting` until the 10 s timeout and then showed a confusing
    /// "no respondió" failure for a connection nobody wanted anymore.
    public mutating func routeDeselected() {
        guard case .connecting = phase else { return }
        phase = .idle
        selectedRouteName = nil
    }

    /// Back to square one (picker dismissed without selection, failure acked).
    public mutating func reset() {
        phase = .idle
        selectedRouteName = nil
    }
}
