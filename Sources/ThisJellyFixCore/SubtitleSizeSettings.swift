import Foundation

/// Persistent subtitle display preferences. Stored in `UserDefaults`
/// (the same store `@AppStorage` writes to) so the player picks up the
/// value live without a restart.
public struct SubtitleSizeSettings: Sendable, Equatable {

    // MARK: - Keys

    public enum Key {
        /// UserDefaults key for the subtitle relative size multiplier.
        public static let relativeSize = "subtitle.relativeSize"
    }

    // MARK: - Preset sizes

    /// Named size presets the user can pick in Settings.
    public enum RelativeSize: Double, CaseIterable, Sendable, Codable {
        case small  = 0.75
        case medium = 1.0
        case large  = 1.35
        case xlarge = 1.75

        /// Human-readable label shown in the picker.
        public var label: String {
            switch self {
            case .small:  return "Pequeño"
            case .medium: return "Mediano"
            case .large:  return "Grande"
            case .xlarge: return "Muy grande"
            }
        }

        /// True for the default value — shown with "(predeterminado)" in the UI.
        public var isDefault: Bool { self == .medium }
    }

    // MARK: - Properties

    /// Multiplier applied to the subtitle renderer's base font size.
    /// 1.0 = default, 0.75 = smaller, 1.35 = larger, 1.75 = largest.
    public var relativeSize: RelativeSize

    public init(relativeSize: RelativeSize = .medium) {
        self.relativeSize = relativeSize
    }

    // MARK: - Persistence

    public static func current(_ defaults: UserDefaults = .standard) -> SubtitleSizeSettings {
        let raw = defaults.double(forKey: Key.relativeSize)
        let size = RelativeSize(rawValue: raw) ?? .medium
        return SubtitleSizeSettings(relativeSize: size)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(relativeSize.rawValue, forKey: Key.relativeSize)
    }
}
