import Foundation

/// Persistent appearance preference. Stored in `UserDefaults` — the same
/// store `@AppStorage` writes to — so the root view reads it live and the
/// choice survives relaunch.
///
/// Mirrors the shape of `SubtitleSizeSettings` / `LanguagePreferences`: a
/// plain value type in Core, no SwiftUI, no view state.
public struct AppearanceSettings: Sendable, Equatable {

    // MARK: - Keys

    public enum Key {
        /// UserDefaults key for the selected appearance.
        public static let appearance = "appearance.mode"
    }

    // MARK: - Modes

    /// How the app resolves its color scheme.
    public enum Appearance: String, Sendable, CaseIterable, Codable, Hashable {
        /// Follow the system setting — the app must not force a scheme here.
        case system
        /// Always light.
        case light
        /// Always dark.
        case dark

        /// Human-readable label for the picker.
        public var label: String {
            switch self {
            case .system: "Sistema"
            case .light: "Claro"
            case .dark: "Oscuro"
            }
        }
    }

    // MARK: - Properties

    /// The selected appearance.
    public var appearance: Appearance

    public init(appearance: Appearance = .system) {
        self.appearance = appearance
    }

    // MARK: - Persistence

    /// Reads the stored preference. An unknown or missing value means
    /// "follow the system" — never a forced scheme.
    public static func current(_ defaults: UserDefaults = .standard) -> AppearanceSettings {
        let raw = defaults.string(forKey: Key.appearance) ?? ""
        return AppearanceSettings(appearance: Appearance(rawValue: raw) ?? .system)
    }

    /// Writes the preference.
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(appearance.rawValue, forKey: Key.appearance)
    }
}
