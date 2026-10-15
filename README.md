<p align="center">
  <img src="icono.png" width="120" alt="ThisJellyFix icon" />
</p>

<h1 align="center">ThisJellyFix</h1>

<p align="center">
  Native Jellyfin client for Apple platforms, with a cinematic experience called <strong>La Marea</strong>.
  <br />
  Cliente Jellyfin nativo para Apple, con experiencia cinematográfica <strong>La Marea</strong>.
</p>

<p align="center">
  <a href="https://github.com/THISJOWI/THISJELLYFIX/actions/workflows/ci.yml"><img src="https://github.com/THISJOWI/THISJELLYFIX/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <img src="https://img.shields.io/badge/Swift-5.10-orange?logo=swift" alt="Swift 5.10" />
  <img src="https://img.shields.io/badge/iOS-17%2B-blue?logo=apple" alt="iOS 17+" />
  <img src="https://img.shields.io/badge/macOS-14%2B-blue?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/tvOS-17%2B-black?logo=apple" alt="tvOS 17+" />
  <img src="https://img.shields.io/badge/visionOS-1%2B-purple?logo=apple" alt="visionOS 1+" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/THISJOWI/THISJELLYFIX" alt="License: MIT" /></a>
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen" alt="SPM" />
  <img src="https://img.shields.io/badge/XcodeGen-required-lightgrey" alt="XcodeGen" />
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#español">Español</a>
</p>

---

## English

**ThisJellyFix** is a native SwiftUI Jellyfin client for iOS, macOS, tvOS and visionOS. No web wrapper, no Electron — pure Apple frameworks (AVFoundation, SwiftUI, Keychain, Spotlight, App Intents).

### Features

- **La Marea home** — cinematic rows, continue watching, novelty classifier, recommendations
- **Auth** — server probe (`System/Info/Public`), login with Jellyfin users, Keychain storage, multi-server, user avatar in profile
- **Library** — grid, detail views, search, favorites, chapters, cast info
- **Player** — AVFoundation engine, direct play, stream quality picker + bitrate capping, manual resume, client-side subtitle overlay, volume-normalized subs
- **Living room** — AirPlay route state, Google Cast (iOS only, SDK 4.8.6), Handoff between devices (old device stops when another takes over), PiP with handoff policy
- **Offline** — download queue + coordinator, per-quality download options
- **Integrations** — \*Arr clients, TMDB metadata provider, Jellyfin segments (intro/credits markers)
- **System** — Spotlight indexing, App Intents, Handoff activities, Now Playing info

> iOS target doubles as iPadOS. Cast exists only on iOS — Google ships no native macOS/tvOS/visionOS sender SDK.

### Screenshots

| iOS | macOS | tvOS |
|-----|-------|------|
| *pending `ios-home.png`* | *pending `macos-home.png`* | *pending `tvos-home.png`* |

> Placeholders until real captures land. See [Docs/screenshots/README.md](Docs/screenshots/README.md).

### Quickstart

Requirements: Xcode 16+, Swift 5.10, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/THISJOWI/THISJELLYFIX.git
cd THISJELLYFIX
xcodegen
open thisjellyfix.xcodeproj
```

Run the target matching your device/simulator (iOS, macOS, tvOS, visionOS).

SPM also works for the shared modules:

```bash
swift build
swift test
```

### Project layout

```
Apps/            # SwiftUI entry points per platform (iOS, macOS, tvOS, visionOS)
Sources/
  ThisJellyFixCore/        # Domain: catalog, playback profile, subtitles, handoff, keychain
  ThisJellyFixNetworking/  # Jellyfin API: auth, library, playback, subs, probe
  ThisJellyFixDiscovery/   # Discovery, recommenders, downloads, TMDB, *Arr
  ThisJellyFixFeature/     # SwiftUI: Marea UI, login, library, player, settings
  ThisJellyFixPlayback/    # AVPlaybackEngine, NowPlaying, AirPlay state
  ThisJellyFixCast/        # Google Cast wrapper (iOS only, canImport-gated)
Tests/           # Matching *Tests targets per module
Docs/            # specs/, plans/, COMPATIBILITY.md
```

### Compatibility

See [Docs/COMPATIBILITY.md](Docs/COMPATIBILITY.md) for the universal-engine decision and license strategy (zero external deps except Cast SDK on iOS).

### Roadmap

- [x] Server discovery + login + Keychain
- [x] Library, search, favorites, detail
- [x] AVFoundation player + quality picker + subs overlay
- [x] Cast (iOS), AirPlay, Handoff, PiP
- [x] Downloads
- [ ] Offline playback hardening
- [ ] visionOS spatial polish
- [ ] TestFlight public beta

### Contributing

PRs welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), open an issue first for big changes. Be kind — see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

### License

[MIT](LICENSE) © THISJOWI.

---

## Español

**ThisJellyFix** es un cliente Jellyfin nativo en SwiftUI para iOS, macOS, tvOS y visionOS. Nada de webviews — frameworks Apple puros (AVFoundation, SwiftUI, Keychain, Spotlight, App Intents).

### Funcionalidades

- **Inicio La Marea** — filas cinematográficas, seguir viendo, clasificador de novedades, recomendaciones
- **Auth** — probe de servidor (`System/Info/Public`), login con usuarios Jellyfin, Keychain, multiservidor, foto de usuario en perfil
- **Biblioteca** — parrilla, detalle, búsqueda, favoritos, capítulos, reparto
- **Reproductor** — motor AVFoundation, reproducción directa, selector de calidad + límite de bitrate, resume manual, subtítulos overlay lado cliente
- **Salón** — AirPlay, Google Cast (solo iOS, SDK 4.8.6), Handoff entre dispositivos (el anterior se detiene), PiP con política de handoff
- **Offline** — cola de descargas con opciones por calidad
- **Integraciones** — clientes \*Arr, metadatos TMDB, marcadores de segmentos (intro/créditos)
- **Sistema** — indexado Spotlight, App Intents, Handoff, Now Playing

> El destino iOS cubre iPhone + iPad. Cast solo en iOS: Google no publica SDK sender para macOS/tvOS/visionOS.

### Capturas

Misma tabla de arriba. Placeholders hasta subir capturas reales.

### Instalación

Requisitos: Xcode 16+, Swift 5.10, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/THISJOWI/THISJELLYFIX.git
cd THISJELLYFIX
xcodegen
open thisjellyfix.xcodeproj
```

Ejecuta el target de tu dispositivo/simulador. Módulos compartidos también por SPM:

```bash
swift build
swift test
```

### Estructura

Igual que el árbol de arriba: `Apps/` por plataforma, `Sources/` por módulo, `Tests/` espejo, `Docs/` con specs y planes.

### Compatibilidad

Ver [Docs/COMPATIBILITY.md](Docs/COMPATIBILITY.md) — decisión de motor universal y estrategia de licencia (cero dependencias salvo Cast en iOS).

### Roadmap

Igual que arriba. PRs bienvenidos — lee [CONTRIBUTING.md](CONTRIBUTING.md).

### Licencia

[MIT](LICENSE) © THISJOWI.

---

### Topics sugeridos (añadir en GitHub → About → ⚙️)

`jellyfin`, `swiftui`, `ios`, `macos`, `tvos`, `visionos`, `avfoundation`, `selfhosted`, `media-client`, `google-cast`, `airplay`, `marea`
