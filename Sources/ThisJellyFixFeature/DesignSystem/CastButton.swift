import SwiftUI

/// Glifo Cast (Chromecast) dibujado a mano: pantalla con las tres ondas de
/// emisión. SF Symbols no incluye el logo Cast de Google, y sustituirlo por
/// "airplayvideo" confundiría Cast con AirPlay (requisito explícito:
/// no confundir ambas tecnologías).
struct CastIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Coordenadas relativas del logo Cast clásico (esquinas
        // inferior-izquierda del rectángulo).
        let w = rect.width, h = rect.height

        // Pantalla (esquina inferior izquierda): cuarto de círculo + líneas.
        path.move(to: CGPoint(x: rect.minX + 0.05 * w, y: rect.minY + 0.80 * h))
        path.addLine(to: CGPoint(x: rect.minX + 0.05 * w, y: rect.minY + 0.95 * h))
        path.addLine(to: CGPoint(x: rect.minX + 0.34 * w, y: rect.minY + 0.95 * h))
        path.addArc(
            center: CGPoint(x: rect.minX + 0.05 * w, y: rect.minY + 0.95 * h),
            radius: 0.29 * w,
            startAngle: .degrees(0),
            endAngle: .degrees(-90),
            clockwise: true
        )
        path.closeSubpath()

        // Tres arcos concéntricos (las ondas), abiertos hacia abajo-izquierda.
        for (index, factor) in [0.16, 0.34, 0.52].enumerated() {
            let radius = factor * w
            let center = CGPoint(x: rect.minX + 0.05 * w, y: rect.minY + 0.95 * h)
            path.move(to: CGPoint(x: center.x + radius, y: center.y))
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )
            _ = index
        }
        return path.strokedPath(StrokeStyle(lineWidth: max(1.5, 0.055 * w), lineCap: .round, lineJoin: .round))
    }
}

/// Botón Cast del player: glifo + estado. Muestra punto rojo de conexión y
/// nombre del dispositivo vía `accessibilityLabel`. Al pulsar abre el
/// selector (`onTap`), o desconecta directamente si ya hay sesión y el
/// usuario pulsa manteniendo... no: pulsar siempre abre el selector, que es
/// donde vive desconectar (patrón de las apps de streaming).
struct CastButton: View {
    let isConnected: Bool
    let isConnecting: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                CastIcon()
                    .stroke(.white, lineWidth: 0)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 16)
                    .overlay(CastIcon().stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round)))
                    .frame(width: 40, height: 40)

                if isConnecting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                        .offset(x: 4, y: -2)
                } else if isConnected {
                    Circle()
                        .fill(MareaTheme.Colors.accent)
                        .frame(width: 8, height: 8)
                        .offset(x: -2, y: -1)
                }
            }
        }
        .background(.black.opacity(0.4), in: Circle())
        .accessibilityLabel(isConnected ? "Cast: conectado" : "Cast")
    }
}
