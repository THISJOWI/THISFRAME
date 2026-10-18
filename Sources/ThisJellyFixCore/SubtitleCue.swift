import Foundation

/// One timed subtitle line (SRT-style). Times are seconds from media start.
public struct SubtitleCue: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    public func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }
}

/// Minimal SRT parser for external subtitle files delivered by Jellyfin
/// (`/Videos/{id}/Subtitles/{i}/Stream.srt`). ASS/PGS never reach here —
/// the device profile asks the server to deliver those as text or burn them.
public enum SRTParser {
    /// Parses SRT content into cues sorted by start time. Malformed blocks
    /// are skipped — one bad timestamp must not kill the whole track.
    public static func parse(_ content: String) -> [SubtitleCue] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        // Split on blank lines; each block = index / timing / text.
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  let cue = parseBlock(lines: lines, timingIndex: timingIndex)
            else { continue }
            cues.append(cue)
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func parseBlock(lines: [String], timingIndex: Int) -> SubtitleCue? {
        let timing = lines[timingIndex]
        let parts = timing.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let startRaw = parts[0].trimmingCharacters(in: .whitespaces)
        // End side may carry position/align settings after the timestamp.
        let endRaw = parts[1]
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .first ?? ""
        guard let start = parseTimestamp(startRaw), let end = parseTimestamp(endRaw) else { return nil }

        let textLines = lines[(timingIndex + 1)...]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !textLines.isEmpty else { return nil }
        let text = sanitize(textLines.joined(separator: "\n"))
        guard !text.isEmpty else { return nil }
        return SubtitleCue(start: start, end: end, text: text)
    }

    /// Limpia restos de formato ASS/SSA que sobreviven a la conversión a SRT
    /// del servidor (`{\fad…\pos…}`, `\N`, `\h`, `\an8`…): son instrucciones
    /// de render, nunca diálogo. Solo toca SINTAXIS de formato:
    /// - bloques `{...}` que contienen una contrabarra (los literales como
    ///   `{hola}` se conservan),
    /// - `\N`/`\n` (saltos ASS) → salto de línea, `\h` → espacio,
    /// - demás códigos `\comando` o `\comando(params)` → eliminados.
    /// - etiquetas HTML de formato (`<i>`, `<font>`, …) → eliminadas, dejando
    ///   el diálogo; `<br>` se convierte en salto de línea.
    /// El texto visible no se filtra ni se reordena.
    static func sanitize(_ raw: String) -> String {
        var text = raw
        // Bloques override con formato: {\...} (multilínea incluida).
        if let blockRegex = try? NSRegularExpression(
            pattern: #"\{[^}]*\\[^}]*\}"#,
            options: [.dotMatchesLineSeparators]
        ) {
            text = blockRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        text = text.replacingOccurrences(of: "\\N", with: "\n")
        text = text.replacingOccurrences(of: "\\n", with: "\n")
        text = text.replacingOccurrences(of: "\\h", with: " ")
        // Códigos sueltos: \fad(0,200), \an8, \bord0, \c&HFFFFFF& …
        if let codeRegex = try? NSRegularExpression(pattern: #"\\[A-Za-z]+(\([^)]*\))?[0-9&]*"#, options: []) {
            text = codeRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        text = stripHTMLMarkup(text)
        // Normaliza líneas: recorta y colapsa vacías del borrado.
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private static func stripHTMLMarkup(_ raw: String) -> String {
        var text = raw
        if let lineBreakRegex = try? NSRegularExpression(
            pattern: #"<br\s*/?>"#,
            options: [.caseInsensitive]
        ) {
            text = lineBreakRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\n"
            )
        }
        if let tagRegex = try? NSRegularExpression(
            pattern: #"</?[A-Za-z][A-Za-z0-9]*(?:\s+[^<>]*?)?\s*/?>"#,
            options: [.caseInsensitive]
        ) {
            text = tagRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        return decodeHTMLEntities(in: text)
    }

    private static func decodeHTMLEntities(in raw: String) -> String {
        let namedEntities = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"",
            "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
            "hellip": "…", "lsquo": "‘", "rsquo": "’",
            "ldquo": "“", "rdquo": "”"
        ]
        guard let regex = try? NSRegularExpression(
            pattern: #"&(#(?:x[0-9A-Fa-f]+|[0-9]+)|[A-Za-z]+);"#,
            options: []
        ) else { return raw }

        let result = NSMutableString(string: raw)
        for match in regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).reversed() {
            guard let entityRange = Range(match.range(at: 1), in: raw) else { continue }
            let entity = String(raw[entityRange])
            let replacement: String?
            if entity.hasPrefix("#x"), let value = UInt32(entity.dropFirst(2), radix: 16),
               let scalar = UnicodeScalar(value) {
                replacement = String(scalar)
            } else if entity.hasPrefix("#"), let value = UInt32(entity.dropFirst()),
                      let scalar = UnicodeScalar(value) {
                replacement = String(scalar)
            } else {
                replacement = namedEntities[entity.lowercased()]
            }
            if let replacement {
                result.replaceCharacters(in: match.range, with: replacement)
            }
        }
        return result as String
    }

    /// `HH:MM:SS,mmm` or `HH:MM:SS.mmm` → seconds.
    static func parseTimestamp(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2])
        else { return nil }
        return h * 3600 + m * 60 + s
    }

    /// The cue active at `time`, or nil (binary search — the timer hits this
    /// every tick over potentially thousands of cues).
    public static func cue(at time: Double, in cues: [SubtitleCue]) -> SubtitleCue? {
        var lo = 0
        var hi = cues.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cue = cues[mid]
            if time < cue.start {
                hi = mid - 1
            } else if time >= cue.end {
                lo = mid + 1
            } else {
                return cue
            }
        }
        return nil
    }
}
