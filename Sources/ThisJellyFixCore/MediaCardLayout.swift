import Foundation

/// Geometry of the media cards, kept in Core so every surface that shows
/// artwork (Home rows, library grid, search grid, favourites) measures the
/// same way and the rules can be unit tested without SwiftUI.
///
/// Two rules drive the whole thing:
/// - a card never grows past the space its container offers it, and
/// - the artwork box always keeps the aspect ratio of the card shape, so a
///   portrait poster is never blown up into a landscape tile.
public enum MediaCardLayout {
    /// Shape of the artwork a card shows.
    public enum Shape: String, Sendable, Equatable, CaseIterable {
        /// 2:3 vertical poster — movies and series.
        case poster
        /// 16:9 landscape frame — episodes and the "continue watching" card.
        case landscape

        /// width / height of the artwork box.
        public var aspectRatio: CGFloat {
            switch self {
            case .poster: 2.0 / 3.0
            case .landscape: 16.0 / 9.0
            }
        }
    }

    /// How a card takes its width inside its container.
    public enum Width: Sendable, Equatable {
        /// A fixed width. Used by rows that scroll horizontally: the designed
        /// size is the point there and nothing can overflow.
        case fixed(CGFloat)
        /// Fill the offered width. Used by adaptive grids, where a fixed
        /// width would spill out of the column and collide with the next
        /// cell — the cause of the "episode cover far too large" report.
        case flexible
    }

    /// Height a card of `width` needs for `shape`.
    public static func height(forWidth width: CGFloat, shape: Shape) -> CGFloat {
        guard width > 0 else { return 0 }
        return (width / shape.aspectRatio).rounded()
    }
}
