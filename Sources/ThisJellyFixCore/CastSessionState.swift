import Foundation

/// Ciclo de vida de una sesión de Google Cast — máquina de estados pura,
/// sin dependencia del SDK (unit-testeable con `swift test` en macOS).
///
/// Espejo deliberado de `AirPlayRouteState` (mismo patrón de fases y
/// guardas) para que la convivencia AirPlay/Cast sea simétrica: la UI
/// aprende un solo modelo de "salida remota".
///
/// Diferencia clave con AirPlay: AirPlay la negocia AVPlayer y el engine
/// solo observa; Cast lo gestionamos nosotros (sesión GCK explícita), así
/// que la máquina también acepta "descubrimiento" como fase propia.
public struct CastSessionState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Sin sesión Cast — reproducción local normal.
        case idle
        /// Escaneando la red (startDiscovery activo, aún sin conexión).
        case discovering
        /// Conectando con un dispositivo elegido por el usuario.
        case connecting(deviceName: String)
        /// Sesión viva con el receptor. El contenido puede o no estar cargado.
        case connected(deviceName: String)
        /// El intento de conexión/conexión falló o la sesión cayó.
        case failed(reason: String)
    }

    public private(set) var phase: Phase = .idle

    /// Último dispositivo con el que hubo sesión (nil hasta la primera
    /// conexión). Sirve para reconectar y para mostrar "última salida".
    public private(set) var lastDeviceName: String?

    public init() {}

    public var isConnecting: Bool {
        if case .connecting = phase { return true }
        return false
    }

    public var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    /// Mientras la sesión negocia, los comandos de transporte deben
    /// encolarse o ignorarse — mismo motivo que en AirPlay.
    public var blocksTransportCommands: Bool { isConnecting }

    // MARK: - Eventos

    /// El usuario abrió el selector / pidió escanear.
    public mutating func discoveryRequested() {
        // Conectado no vuelve a escanear: eso tiraría la sesión viva.
        guard !isConnected else { return }
        phase = .discovering
    }

    /// El usuario eligió un dispositivo concreto.
    public mutating func deviceSelected(name: String) {
        lastDeviceName = name
        phase = .connecting(deviceName: name)
    }

    /// El session manager confirmó la sesión (GCKSession didStart).
    public mutating func sessionStarted(name: String) {
        // Solo acepta si esperábamos a ese mismo dispositivo: un evento
        // tardío de un intento viejo no reemplaza una sesión viva.
        guard case .connecting(let expected) = phase, expected == name else { return }
        lastDeviceName = name
        phase = .connected(deviceName: name)
    }

    /// La sesión se cerró limpiamente (por elección del usuario o del app).
    public mutating func sessionEnded() {
        guard isConnected || isConnecting else { return }
        phase = .idle
    }

    /// Error de conexión o caída inesperada de la sesión viva.
    public mutating func failed(reason: String) {
        // Un fallo tardío de un intento viejo NO pisa una sesión viva.
        guard !isConnected else { return }
        phase = .failed(reason: reason)
    }

    /// El usuario descartó el fallo / cerró el selector.
    public mutating func acknowledgeFailure() {
        if case .failed = phase { phase = .idle }
    }

    /// Limpieza total (cierre de sesión de la app, teardown del player).
    public mutating func reset() {
        phase = .idle
        lastDeviceName = nil
    }
}
