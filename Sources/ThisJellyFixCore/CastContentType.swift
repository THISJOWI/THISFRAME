import Foundation

/// MIME type que el receptor Cast necesita en `MediaInformation.contentType`.
/// Detectado de la extensión de la URL resuelta (Jellyfin la sirve siempre
/// con extensión: master.m3u8 / stream.mp4 / stream).
public enum CastContentType {
    /// `application/x-mpegURL` — lo que el Default Media Receiver espera
    /// para HLS (los tags de streaming_protocols documentan MSE sobre HLS).
    public static let hls = "application/x-mpegURL"
    public static let mp4 = "video/mp4"
    /// Fallback conservador: el servidor Jellyfin sirve mp4/mkv-remux bajo
    /// `/stream` sin extensión, y el Default Receiver mejor mp4 que nada.
    public static let unknownStream = "video/mp4"

    public static func detect(from url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return hls
        case "mp4", "m4v": return mp4
        default: return unknownStream
        }
    }
}
