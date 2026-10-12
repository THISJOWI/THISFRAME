import Foundation

/// Preflight de la URL de stream ANTES de enviársela a un receptor Cast.
///
/// El Chromecast descarga la URL él mismo, desde la red local: no comparte
/// la sesión del remitente ni el contexto de red del dispositivo Apple.
/// Una URL que AVPlayer abre perfectamente puede ser inaccesible para el
/// receptor — este tipo es el filtro que lo impide (y explica el porqué,
/// en vez de fallar con el error opaco del receiver).
public enum CastStreamPreflight {
    public enum Verdict: Equatable, Sendable {
        /// La URL es apta para enviarse al receptor.
        case ok
        /// Rechazada — la razón es presentable al usuario.
        case rejected(reason: String)
    }

    /// Hosts de loopback en todas sus formas. El receptor Cast nunca puede
    /// abrirlos: `localhost` del Chromecast es el propio Chromecast.
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0", "[::1]"]

    /// Valida `url` para reproducción en un receptor Cast.
    public static func validate(_ url: URL) -> Verdict {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .rejected(reason: "La URL de reproducción no es http(s).")
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .rejected(reason: "La URL de reproducción no tiene host.")
        }
        if loopbackHosts.contains(host) {
            return .rejected(
                reason: "El servidor apunta a localhost: el receptor Cast necesita una URL accesible desde la red local (IP o nombre DNS)."
            )
        }
        return .ok
    }

    /// true cuando la URL ya lleva un ApiKey en la query — el receptor no
    /// manda cabeceras, así que SIN query-auth la reproducción moriría con
    /// 401 dentro del Chromecast, imposible de diagnosticar desde la app.
    public static func carriesApiKey(_ url: URL) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }
        return items.contains { $0.name.lowercased().replacingOccurrences(of: "_", with: "") == "apikey" }
    }

    /// Validación completa: accesible + autenticada. `token` se usa SOLO para
    /// comparar — nunca se imprime ni se incluye en el motivo.
    public static func validateForReceiver(_ url: URL) -> Verdict {
        let verdict = validate(url)
        guard case .ok = verdict else { return verdict }
        guard carriesApiKey(url) else {
            return .rejected(reason: "La URL de reproducción no lleva credenciales: el receptor la rechazaría (401).")
        }
        return .ok
    }
}
