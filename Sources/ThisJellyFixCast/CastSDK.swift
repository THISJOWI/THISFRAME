import Foundation
import GoogleCast
import ThisJellyFixCore

/// Bootstrap del SDK de Google Cast (iOS únicamente).
///
/// `GCKCastContext.setSharedInstance` es un proceso por app: llamarlo dos
/// veces lanza. Este wrapper idempotente es el ÚNICO punto de entrada — la
/// app lo invoca una vez en el arranque (AppDelegate) y todo lo demás
/// (descubrimiento, sesiones, media) cuelga del shared context.
///
/// El receiverApplicationID define qué app se lanza en el Chromecast:
/// - CC1AD845 = Default Media Receiver (Google): HLS/DASH/MP4 por URL,
///   sin registro en la Cast Developer Console. Es el punto de partida.
/// - Un receptor personalizado (registrado en cast.google.com/publish)
///   sería necesario solo si necesitáramos lógica propia en el receptor
///   (p. ej. credenciado por customData, UI a medida). Hoy no aplica:
///   la URL de Jellyfin ya lleva ApiKey en la query.
public enum CastSDK {
    /// Default Media Receiver de Google.
    public static let defaultReceiverAppID = "CC1AD845"

    private static let lock = NSLock()
    private static var initialized = false

    /// Inicializa el shared context de Cast una sola vez (thread-safe).
    /// Llamadas posteriores son no-ops: imposible duplicar la inicialización.
    @discardableResult
    public static func initialize(receiverAppID: String = defaultReceiverAppID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !initialized else { return false }

        let criteria = GCKDiscoveryCriteria(applicationID: receiverAppID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        // El SDK 4.5+ desactivó el auto-arranque del descubrimiento: con un
        // selector propio hay que pedirlo explícitamente (lo hace
        // CastDeviceMonitor.startDiscovery). No forzamos aquí para no escanear
        // la red cuando nadie va a usar Cast.
        options.startDiscoveryAfterFirstTapOnCastButton = false
        // Las sesiones NO se suspenden al pasar a segundo plano: el objetivo
        // de la feature es que el Chromecast siga reproduciendo con la app
        // en background o bloqueada.
        options.suspendSessionsWhenBackgrounded = false

        // ObjC `setSharedInstanceWithOptions:error:` → Swift importa
        // `setSharedInstanceWith(_:)` throws. Fallible: options inválidas
        // devuelven error sin tumbar la app.
        do {
            try GCKCastContext.setSharedInstanceWith(options)
        } catch {
            TJFLog("cast: SDK init FAILED \(error.localizedDescription)")
            return false
        }
        initialized = true
        TJFLog("cast: SDK initialized receiverAppID=\(receiverAppID)")
        return true
    }

    /// true cuando `initialize` corrió en este proceso.
    public static var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return initialized
    }
}
