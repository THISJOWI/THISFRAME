import Foundation

/// Robust parser for Jellyfin's ISO8601 wire dates.
///
/// The server emits timestamps like `2026-10-11T18:32:05.1234567Z` — a
/// 7-digit fractional second that `ISO8601DateFormatter` (and JSONDecoder's
/// default strategies) reject. Truncating the fraction to milliseconds keeps
/// sub-second precision far beyond what novelty classification needs while
/// making every Jellyfin date parseable.
public enum JellyfinDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain = ISO8601DateFormatter()

    /// Parses a Jellyfin wire date. Returns nil for nil/empty/malformed input
    /// so callers can treat "no date" as "no novelty claim" (never guess).
    public static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = fractional.date(from: raw) {
            return date
        }
        // Fractional seconds with more than 3 digits: truncate to ms.
        if let dot = raw.firstIndex(of: ".") {
            let tailStart = raw[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" }) ?? raw.endIndex
            let head = String(raw[..<dot])
            let tail = String(raw[tailStart...])
            let digits = raw[raw.index(after: dot)..<tailStart]
            if digits.count > 3 {
                let ms = String(digits.prefix(3))
                return fractional.date(from: head + "." + ms + tail)
                    ?? plain.date(from: head + tail)
            }
        }
        return plain.date(from: raw)
    }
}
