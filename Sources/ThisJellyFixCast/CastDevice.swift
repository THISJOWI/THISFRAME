import Foundation
import ThisJellyFixCore

/// Dispositivo Cast descubierto en la red — modelo inyectable para la UI,
/// independiente de `GCKDevice` (que solo existe en iOS y no es Sendable).
public struct CastDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// true cuando el dispositivo reporta que YA reproduce algo (otra app):
    /// conectar lo robará — la UI lo muestra como aviso, no como bloqueo.
    public let isBusy: Bool

    public init(id: String, name: String, isBusy: Bool) {
        self.id = id
        self.name = name
        self.isBusy = isBusy
    }
}
