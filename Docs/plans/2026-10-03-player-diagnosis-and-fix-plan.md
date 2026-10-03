# Plan técnico — diagnóstico y solución del reproductor (ThisJellyfix)

> **For agentic workers:** this is an INVESTIGATION + SOLUTION plan, not an implementation. Nothing may be modified until each phase's diagnosis step confirms the hypothesis. Phases are ordered by priority; each phase's tasks use checkbox (`- [ ]`) syntax for tracking.

**Goal:** diagnosticar y resolver 7 problemas del reproductor (subtítulos duplicados, fullscreen Mac, botones fullscreen/AirPlay Mac, action pill → Liquid Glass, AirPlay en Lock Screen, reproducción continua, PiP automático al salir) con arquitectura limpia, APIs nativas de Apple y comportamiento consistente en iPhone, iPad, Mac y Apple TV.

**Architecture:** la app ya tiene un núcleo correcto — UN `AVPlayer`/`AVPlayerLayer` (`AVPlaybackEngine`), UN view model `@MainActor` (`PlayerViewModel`), una vista de reproductor compartida (`PlayerView`) y coordinadores de sesión (`PipCoordinator`, `NowPlayingController`). El plan refuerza esas piezas en lugar de crear otras nuevas: fuente única de renderizado de subtítulos, política única de lifecycle de sesión (PiP/Now Playing/continuidad) y chrome de macOS rediseñado sobre ventanas nativas.

**Tech Stack:** Swift 5.10 · SwiftUI · AVFoundation / AVKit / AppKit / MediaPlayer · Jellyfin REST · SPM + xcodegen (`project.yml`) · XCTest (`Tests/`).
**Specs relacionadas:** `Docs/superpowers/specs/2026-10-03-premium-experience-plan.md` (coherencia estética), requisitos del usuario 2026-10-03 (este documento).

## Global Constraints

- Deployment: iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0 → Liquid Glass (iOS 26 / macOS 26) SIEMPRE con `#available(...)` + fallback; el plan no sube floors.
- Cero dependencias de terceros (filosofía hand-rolled del proyecto).
- Cero hacks: no timers arbitrarios (`Task.sleep(300ms)`), no delays artificiales, no ocultar capas sin entender su origen, no heurísticas de "cualquier ventana" (`NSApp.windows.first`).
- `swift test` en verde al final de cada fase (targets: Core, Networking, Playback, Discovery tests).
- Copy de UI en español (localización ES/EN posterior, no bloquea).
- No romper: Handoff, reporting Jellyfin (play/progress/stop), background audio (`.playback` session), PiP manual, restore-from-PiP, downloads.
- Decidido con el usuario (2026-10-03):
  - "Píldora" a sustituir = **action pill de `DetailView`** (cápsula `.regularMaterial` arriba a la derecha).
  - PiP: **solo automático al salir de la app** (Home/bloqueo). Salir del reproductor DENTRO de la app = cerrar la experiencia, sin PiP. Botón PiP manual se mantiene.
  - Continuación: **auto-advance al final** estilo Netflix (saltar ending + si el usuario no hace nada → siguiente), auto-skip de intro activo.

## Review Focus

Los 5 fallos que más probablemente muerdan a quien ejecute este plan, y dónde se testean:

1. **Exclusividad de subtítulos bajo selección tardía de pistas HLS** (el item preselecciona DESPUÉS de nuestro deselect) → invariante "exactamente un renderer" testeado en Fase 1 (tarea 1.5, test unitario del nuevo `SubtitleSelectionState` + log de violaciones).
2. **Identidad de la ventana en fullscreen macOS** (keyWindow erróneo = fullscreen fantasma) → Fase 2 tareas 2.1-2.2: resolución de ventana por NSViewController/window del representable, log de `window.styleMask` antes/después.
3. **Cambio de política PiP rompe el auto-PiP de background o el restore** → Fase 3: tests de `PiPHandoffPolicy` extendidos (`canAutoStartOnBackground`), matriz manual salida-vs-background.
4. **El swap de episodio pierde selección de idioma/subtítulos o duplica reporting** → Fase 6: `NextEpisodeResolver` testado + tests de carry-over de preferencias en `PlayerViewModel` + asserts de sesión de reporting (un solo play/stop por episodio).
5. **Liquid Glass availability** (builds macOS 14/15/26 e iOS 17/25/26) → Fase 4: compilar los dos branches, snapshot visual en matrix de Reduce Transparency/Reduce Motion.

---

## 0. Relación entre los problemas (req. 8)

No son 7 problemas independientes. El agrupamiento real por componentes:

```
                    ┌──────────────────────────────────────────┐
   P2 fullscreen ──►│  Chrome/presentación en macOS            │◄── P3 botones
   P4 pill ────────►│  PlayerView(#if os) + DetailView(ZStack) │    fullscreen/AirPlay
                    └──────────────────────────────────────────┘
                    ┌──────────────────────────────────────────┐
   P1 subtítulos ──►│  AVPlaybackEngine (media selection)      │
                    │  + PlayerViewModel (overlay externo)     │
                    └──────────────────────────────────────────┘
                    ┌──────────────────────────────────────────┐
   P5 LockScreen ──►│  Ciclo de VIDA de la sesión de           │
   P6 continuidad ─►│  reproducción en PlayerViewModel:        │
   P7 PiP ─────────►│  engine + tracks + NowPlaying + Pip +    │
                    │  reporting + swap de item                │
                    └──────────────────────────────────────────┘
```

- **P2 + P3 son UN problema**: el chrome del reproductor en macOS (overlay SwiftUI + `NSWindow.toggleFullScreen` por keyWindow + `NSPanel` flotante de cierre + paddings fijos). Arreglar el fullscreen sin rediseñar el chrome deja los botones rotos y viceversa.
- **P4 es parcialmente P2**: la action pill vive en `DetailView`, que en macOS es la MISMA ventana que el reproductor (ZStack). La decisión de toolbar/window de la Fase 2 condiciona dónde poner la pill en macOS.
- **P5 + P6 + P7 comparten el ciclo de vida de sesión** en `PlayerViewModel`: activate/deactivate de NowPlaying, float/stop de PiP, `endCurrentItemSession`/`switchToEpisode` y el estado `ended`. Hoy las reglas están repartidas (policy en Core, flags en VM, handlers en coordinador) y cada problema se tocó de forma aislada → cambiar uno sin mirar los otros rompe los demás.
- **Riesgos transversales a auditar en Fase 0**: flags estáticos mutables (`PlayerTeardown.errorFlag`, `PlayerView.presentedCount`) con `nonisolated(unsafe)` — race conditions doc-huerfano; el Timer de 0.5s que dispara `Task { @MainActor }` (cada tick = posible reordenación de updates); `engine.onStateChanged` con doble hop; `@unchecked Sendable` en el engine.

### Componentes a revisar primero (orden)

| # | Componente | Archivo | Problemas que toca |
|---|---|---|---|
| 1 | Ciclo de vida de sesión de `PlayerViewModel` | `Sources/ThisJellyFixFeature/PlayerViewModel.swift` (1081 líneas, 10 responsabilidades) | P5, P6, P7 |
| 2 | Chrome y presentación en macOS | `PlayerView.swift:247-340, 616-658, 1250-1422` + `DetailView.swift:48-88` | P2, P3, P4 |
| 3 | Selección de medios en el engine | `AVPlaybackEngine.swift:43-59, 211-243, 308-390` | P1 |
| 4 | Política PiP | `PiPHandoffPolicy.swift`, `PipCoordinator.swift:82-132`, `PlayerViewModel.swift:1056-1080` | P7, P5 |
| 5 | Now Playing | `NowPlaying.swift`, `PlayerViewModel.swift:149-159, 513-518, 969-997` | P5, P6 |
| 6 | Resolución de siguiente episodio | `DirectPlayer.swift:155-201`, `DetailView.swift:634-652` | P6 |

---

## 1. Prioridades (orden de ejecución)

| Fase | Problema | Impacto | Esfuerzo | Por qué aquí |
|---|---|---|---|---|
| **0** | Instrumentación base + corpus de reproducción | habilita todo | bajo | sin síntomas reproducibles y logs, cualquier "arreglo" es un hack |
| **1** | P1 subtítulos duplicados | alto (se ve a diario, 4 plataformas) | medio | bug visible y acotado; la invariante de fuente única evita regresiones de formato |
| **2** | P2 + P3 fullscreen y botones Mac | alto (Mac inservible) | alto | un solo rediseño de chrome; P4 depende de su decisión de ventana/toolbar |
| **3** | P7 PiP al salir | alto (molestia diaria) | bajo | cambio de política aislado + tests; reduce ruido mientras se trabaja el resto |
| **4** | P4 action pill → Liquid Glass | medio (estética) | medio | requiere la arquitectura de ventana de la Fase 2 y `#available` checks |
| **5** | P5 Lock Screen / AirPlay sistema | medio (integración) | medio | migración a `MPNowPlayingSession` tras estabilizar el ciclo de vida |
| **6** | P6 reproducción continua | alto (feature) | alto | depende de que PiP/NowPlaying/reporting/swaps ya estén correctos |

---

## 2. Fase 0 — Línea base: corpus, logs y captura (todos los problemas)

**Objetivo:** poder reproducir cada síntoma de forma determinista y saber QUÉ capa lo pinta, antes de tocar nada.

### Corpus de contenido de prueba (preparar en el servidor)

| # | Contenido | Cubre |
|---|---|---|
| C1 | mp4 h264 + pista `mov_text` embebida | Direct Play, subs nativos (Embed) |
| C2 | mkv + `.srt` externo (subtítulo sidecar) | Direct Stream/remux, subs overlay |
| C3 | mkv + `.ass` externo | Encode/quemado + overlay |
| C4 | mp4 con WebVTT embebido / HLS transcoded | Transcoding, renditions HLS |
| C5 | Serie multi-temporada, último episodio de temporada y de serie | Continuidad |
| C6 | Episodio con intro/chapters (plugin de segmentos) | Auto-skip |
| C7 | Formato que fuerza transcode (hevc/av1 no soportado) | Subs durante transcode |

### Logs (usar `TJFLog`, ver `Core/Logging.swift`)

Añadir temporalmente (Fase 0) y mantener los permanentes señalados:

1. **Subtítulos** — en cada tick (0.5s) y en cada cambio: `subtitle: overlay=<texto|nil> native=<option.displayName|off> sel=<índice deseado> method=<directPlay|directStream|transcode>` (permanente, solo en cambios).
2. **Ventana macOS** — antes/después de toggle: `win=<título|ptr> styleMask=<…> isFullScreen=<bool> keyWindow=<ptr>` (permanente).
3. **Hit-testing macOS** — log en acción de cada botón del overlay (`fullscreen tapped`, `routePicker tapped`) para distinguir "no llega el evento" de "la acción falla" (permanente).
4. **PiP** — ya hay buenos logs (`pip: …`); añadir el motivo del gate: `pip: exit handoff denied reason=<userPaused|engineStopped|error|ended|policy>`.
5. **Continuidad** — `ended item=<id> → next=<id|none reason=…>` (permanente).

**Captura:** Console.app filtrando `TJF` + screenshots con ⌘⇧4 (o `screencapture`) para cada síntoma visual. Guardar en `Docs/bugs/`.

### Tareas Fase 0

- [ ] **0.1** Preparar corpus C1-C7 en el servidor y una entrada "Lab" (o notas en `Docs/bugs/`) con cómo llegar a cada uno.
- [ ] **0.2** Añadir logs 1-5 (solo observación, cero cambios de comportamiento). Commit: `chore(player): diagnostic logging for subtitles, window, pip, queue`.
- [ ] **0.3** Capturar síntoma actual de CADA problema (screenshots + logs) como línea base. Documentar en `Docs/bugs/2026-10-03-player-baseline.md`.
- [ ] **0.4** Verificar que `swift test` sigue verde y que la app compila en los 4 targets.

**Criterio de salida:** para cada uno de los 7 problemas existe un reproducción + log + screenshot que lo demuestra.

---

## 3. Problema 1 — Subtítulos duplicados

### 3.1 Síntomas observados
Dos capas de subtítulos simultáneas con prácticamente el mismo texto: una con fondo negro, otra sin fondo.

### 3.2 Análisis del código (evidencia)

Hay **DOS renderizadores** en `PlayerView`:

| Renderer | Dónde | Estilo |
|---|---|---|
| **Nativo** — `AVPlayerLayer` vía `AVMediaSelection` (legible group) | `AVPlaybackEngine.swift:211-243` (selección) + pintado interno de AVFoundation | Texto del sistema (AVFoundation aplica su propio estilo; según formato/OS puede salir con caja oscura o con solo borde/sombra) |
| **Overlay SwiftUI** — SRT externo descargado y parseado | `PlayerView.swift:231-245` (`viewModel.subtitleText`), estilo `.title3.semibold` + `.background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))` | Caja negra 55% explícita |

Estrategia actual declarada en `AVPlaybackEngine.swift:12-17`: embebidos → nativo; SRT externo → overlay; ASS/PGS → quemado por el servidor (`PlaybackDeviceProfile.avPlayer`, `SubtitleProfiles` en `PlaybackDeviceProfile.swift:151-163`: srt/subrip/webvtt `External`, ass/ssa/pgs `Encode`, mov_text/tx3g `Embed`).

Defensas ya presentes (¡se han corregido esta zona antes — los comments lo documentan!):
- `appliesMediaSelectionCriteriaAutomatically = false` (`AVPlaybackEngine.swift:59`).
- Re-assert de `desiredSubtitleIndex` en `.ready` y tras `loadTracks` (`:330, :386`) porque "AVPlayerItem puede preseleccionar su default DESPUÉS de nuestro deselect — esa carrera dibujaba subs nativos junto al overlay".

### 3.3 Hipótesis (ordenadas por probabilidad)

- **H1 — Doble pertenencia de la MISMA pista**: el servidor entrega el subtítulo como EXTERNO (app lo baja → overlay) y el asset entregado TAMBIÉN lo contiene embebido (remux mkv→mp4 convierte texto a `mov_text`; HLS lleva rendition WebVTT). La selección nativa no queda apagada (carrera de preselección del item, sobre todo en HLS que aterriza tarde) → mismo texto, dos pintores.
  - *Verificar*: log de §2.1 — si `native=<algo>` mientras `overlay=<texto>`, confirmado.
- **H2 — Doble auto-selección por preferencias**: `applyLanguagePreferences()` se ejecuta dos veces (`loadTracks` y de nuevo al cargar externos, `PlayerViewModel.swift:676-690, 887-890`). El segundo pase está gateado por `selectedSubtitleTrackIndex == nil`, pero si el primer pase elige EMBEBIDO y el item preselecciona otro → dos activos.
  - *Verificar*: logs `langPref subtitles ->` — si aparecen más de una vez con distinto id, confirmado.
- **H3 — Quemado + overlay**: ASS marcado `Encode` se quema en el vídeo (estilo "caja"/tipografía del servidor) y la app además descarga un SRT externo del mismo idioma (si el servidor lo lista `isExternal=true`) → una capa es literalmente píxeles del vídeo (inseparable) y la otra es el overlay.
  - *Verificar*: log `extSubs load idx=… codec=ass` + probar C3.
- **H4 — Dos capas nativas**: imposible hoy (un solo `AVPlayerLayer`, `playerLayer` único compartido con PiP) — descartado salvo evidencia de doble hosting del layer (auditar `PlayerLayerContainer.host` / `PipLayerHostView`).
- **H5 — ¿Cuál es "fondo negro" y cuál "sin fondo"?** — NO asumir: la caja del overlay es `black.opacity(0.55)` (candidata a "fondo negro") y el nativo usa el estilo de AVFoundation (que en HLS WebVTT a veces sale sin caja). Determinar empíricamente con el pase de §3.6.

### 3.4 Componentes a inspeccionar
- `Sources/ThisJellyFixPlayback/AVPlaybackEngine.swift:43-59, 211-243, 308-390`
- `Sources/ThisJellyFixFeature/PlayerViewModel.swift:450-489` (selección), `676-690` (loadTracks), `840-891` (externos)
- `Sources/ThisJellyFixFeature/PlayerView.swift:231-245` (overlay)
- `Sources/ThisJellyFixCore/PlaybackDeviceProfile.swift:151-163` (SubtitleProfiles)
- `Sources/ThisJellyFixNetworking/JellyfinPlaybackClient.swift:27-49` (¿envía `SubtitleStreamIndex`? hoy NO → el servidor no debería quemar por selección; verificar si aun así quema con ASS)

### 3.5 APIs de Apple implicadas
`AVMediaSelectionGroup/Option`, `AVPlayerItem.select(_:in:)`, `AVPlayerItem.currentMediaSelection` (KVO), `AVPlayer.appliesMediaSelectionCriteriaAutomatically`, `AVMediaSelectionCharacteristic.legible`, `AVTextStyleRule` (si se quisiera estilizar el nativo), `AVPlayerLayer` (render nativo), SwiftUI `Text` overlay. WebVTT/SRT/ASS/SSA: formatos de entrada, no APIs.

### 3.6 Cómo reproducir / diagnosticar la causa real

1. Reproducir C1, C2, C3, C4, C7 con subtítulo preferido activo. Capturar screenshot.
2. **Test decisivo — "Desactivados"**: abrir el picker → Desactivados → ¿desaparece AMBAS capas?
   - Desaparecen ambas → los dos renderizadores responden a nuestra selección; la causa es una **selección duplicada** (H1/H2) → mirar logs.
   - Sigue UNA capa → esa capa **ignora** nuestra selección (carrera de preselección del item en HLS, H1) → mirar `native=…` del log.
   - Sigue una capa que además no responde a ningún cambio → es **quemado** (H3) → `extSubs` log + C3.
3. Test de estilado: si la capa "con fondo negro" es la NATIVA (AVFoundation), es su estilo por defecto → se cambia con `AVTextStyleRule` (color/caja transparentes) o se unifica estilo en el overlay.
4. Contar capas con el log de §2.1 durante 30s de reproducción por caso.

### 3.7 Solución a estudiar (fuente única de renderizado)

Objetivo: **invariante "exactamente un renderer activo"**, no ocultar una capa.

1. **Nuevo estado central** en Core (testable), único dueño de la decisión:
   ```swift
   public enum SubtitleRenderTarget: Equatable {
       case off
       case nativeAVPlayer(optionIndex: Int)   // pintado por AVPlayerLayer
       case swiftOverlay(trackIndex: Int)      // pintado por PlayerView
   }
   public struct SubtitleSelectionState: Equatable {
       public var target: SubtitleRenderTarget
       public var reason: String               // "manual", "languagePreference", "itemDefault"
   }
   ```
2. **Exclusividad dura en el engine**: `applySubtitleSelectionNow()` pasa a ser la ÚNICA puerta a `item.select`; añadir re-assert en `.ready`, en `loadTracks` y — clave — **KVO de `currentMediaSelection`** (verificar disponibilidad al implementar; fallback: re-assert en el tick de 0.5s) para revertir cualquier preselección del item que no sea `desiredSubtitleIndex`. Log permanente cuando se revierte (`subtitles: item preselected X, reverted to Y`).
3. **Deduplicación de pistas** en `PlayerViewModel.loadTracks()`: si una pista externa (server `isExternal`) tiene el MISMO idioma/título que una pista embebida disponible → **gana la embebida** y NO se descarga ni registra el externo. Elimina H1 de raíz sin importar el formato.
4. **Guard de quemado**: si `PlayMethod == .transcode` y el stream externo está marcado para `Encode` (ass/ssa/pgs) → no montar overlay (el vídeo ya lo lleva pintado); log `subtitles: burned by server, overlay skipped`.
5. **Un solo estilo**: definir el estilo canónico UNA vez (capa SwiftUI: `.title3.semibold`, caja opcional configurable) y, si la capa nativa resulta ser la correcta a conservar, estilizar `AVPlayerLayer` con `AVTextStyleRule` (fondo transparente) para que ambas rutas sean visualmente idénticas. Decisión final = la que confirme el §3.6 con usuario ("mantener la sin fondo / la que representa a la app").
6. **Platform check**: `PlayerView` y el engine son compartidos con tvOS/visionOS → la exclusividad aplica en todas; verificar en tvOS (donde el nativo es el estilo canónico de focus).

### 3.8 Qué EVITAR
- Ocultar el overlay con `.opacity(0)`/`if false` "y ya" → el formato que doble-genera volverá a aparecer en otro stream (el usuario lo pidió explícitamente).
- Añadir un timer/delay para "dar tiempo" a que el item cargue (parche; usar re-assert + KVO).
- Desactivar el renderizador nativo globalmente → rompe subs embebidos en Direct Play y en tvOS.
- Descargar SRT cuando la pista ya está embebida (duplica ancho de banda y texto).

### 3.9 Riesgos
- KVO de `currentMediaSelection` podría no ser KVO-compliant en todos los OS → fallback al re-assert por tick (verificado con test en dispositivo).
- Dedupe por idioma puede ocultar un externo mejor (p. ej. "Director's Commentary" embebido vs externo) → dedupe solo cuando idioma+tipo coinciden, mantener ambos en el picker.
- ASS con posicionamiento/estilo se pierde hoy igual (quemado) — no empeorar: no pasar ASS por overlay.

### 3.10 Pruebas
- Unit: `SubtitleSelectionState` (transiciones, invariantes), dedupe embebido/externo (CoreTests).
- Manual matrix completa en §11 (bloque Subtítulos) × (Direct Play / Direct Stream / Transcode).
- `swift test` verde.

### 3.11 Criterio de "resuelto"
- En todo el corpus, en cualquier método de reproducción y plataforma: **una sola capa de subtítulos**, siempre la elegida por el usuario/prefs; log de 30s sin violaciones de invariante; picker sigue listando embebidos + externos; "Desactivados" apaga TODO.

---

## 4. Problema 2 — Fullscreen en macOS

### 4.1 Síntomas
Controles/iconos superpuestos, elementos encima de otros, controles fuera de los límites de ventana, falso fullscreen (parte de pantalla visible), no se siente nativo.

### 4.2 Evidencia de cómo está hoy
- El reproductor NO es una presentación: es un **ZStack dentro de `DetailView`** (`DetailView.swift:69-88`), con toolbar oculto mientras reproduce (`.toolbar(showPlayer ? .hidden : .visible, for: .windowToolbar)`, `:53`).
- Fullscreen = `NSApp.keyWindow?.toggleFullScreen(nil)` (`PlayerView.swift:254-259`) — **heurística de keyWindow**.
- Botón de cierre = **`NSPanel` flotante propio** (`CloseButtonWindowRepresentable`, `PlayerView.swift:1250-1422`), con `level = .floating`, `canJoinAllSpaces`, reposicionado por observador de frame + `Task.sleep(300ms)` (`:1366-1369`) — el comment admite: *"After toggleFullScreen, SwiftUI overlay buttons lose hit testing"*.
- Controles con **paddings fijos** (`.padding(.top, 8)`, `.bottom 12/140`, `PlayerView.swift:854, 932, 310`) sin leer `safeAreaInsets`.
- El layer de vídeo se aloja en un `NSViewRepresentable` que redimensiona sublayers en `layout()` (`:629-658`).

### 4.3 Hipótesis
- **H1 — keyWindow equivocado**: `NSApp.keyWindow` puede ser un sheet, el `NSPanel` (aunque sea `.nonactivatingPanel`), el Spotlight o una ventana de otra escena → se toggla otra ventana → "aparenta fullscreen pero no lo es" / la ventana del reproductor queda windowed. *Verificar*: log 2 de Fase 0 (win ptr + styleMask + isFullScreen en cada toggle).
- **H2 — el contenido no llena la ventana**: con toolbar/titlebar presentes o sin `fullSizeContentView`, el ZStack queda bajo el área de titlebar/menubar → bandas visibles, iconos de sistema encima de los controles. En fullscreen real, el menubar auto-hide deja ver bordes si el video no `ignoresSafeArea` completo.
- **H3 — el NSPanel flotante se solapa**: visible en fullscreen (se ordena por frame del "player window" mal identificado por título, `:1410-1419`), reposicionado con sleep → icono encima de otro. Candidato directo a "superposición de iconos".
- **H4 — transición = reestructuración de jerarquía**: el comment indica que tras `toggleFullScreen` los overlays SwiftUI pierden hit-testing; si además el window cambia de instancia, los observers del panel apuntan a la ventana vieja.
- **H5 — coordenadas/safe area**: paddings fijos no respetan notch de MacBook, pantallas externas con distinta altura ni Stage Manager.

### 4.4 Componentes a inspeccionar
`PlayerView.swift:172-340` (stack de overlays), `:616-658` (bridge), `:1250-1422` (panel), `DetailView.swift:47-124` (presentación mac), `Apps/macOS/ThisJellyFixMacOSApp.swift` (WindowGroup), `Apps/macOS/Info.plist`.

### 4.5 APIs de Apple
`NSWindow.toggleFullScreen(_:)`, `NSWindow.StyleMask [.fullScreen, .fullSizeContentView, .titled]`, `NSWindow.willEnter/didEnter/willExit/didExitFullScreenNotification`, `NSWindow.safeAreaInsets` (macOS 12+), `NSWindow.screen`, `NSApp.keyWindow` vs ventana del representable, SwiftUI `.toolbar(_:for: .windowToolbar)`, `.windowStyle(.hiddenTitleBar)`, `.ignoresSafeArea()`, `AVPlayerView` (`controlsStyle`, `allowsEnteringFullScreen`, embebe layer + fullscreen nativo), `AVPlayerViewController` (no disponible en mac AppKit puro → no candidato).

### 4.6 Cómo reproducir
1. Detalle → Reproducir (mac) → botón fullscreen (绿) y botón del overlay → comparar: ¿la ventana entra en `.fullScreen`? ¿el vídeo llena el display? ¿el menubar queda oculto?
2. Repetir: con monitor externo, con Stage Manager, en notch, saliendo con Esc/botón, entrando dos veces seguidas, con sheet de picker abierto (audio/subtítulos).
3. Log 2 de Fase 0 en cada transición.

### 4.7 Cómo determinar la causa
- Si el log muestra `isFullScreen=false` tras pulsar → H1 (ventana equivocada).
- Si `isFullScreen=true` pero quedan bandas → H2/H5 (safe area/layout): medir `window.contentView.frame` vs `videoContainer.frame` en pantalla.
- Si hay un elemento superpuesto que no pertenece al overlay → H3 (el NSPanel): `NSApp.windows` listado en el log debe mostrar el panel.

### 4.8 Solución a estudiar (arquitectura correcta)

**Dirección recomendada — fullscreen nativo de macOS con chrome propio sin window hacks:**

1. **Resolver la ventana de forma correcta, nunca por keyWindow**: el `NSViewRepresentable` del reproductor captura `view.window` en `viewDidMoveToWindow` y expone un callback `onWindowChange`; el fullscreen se ejecuta con `window.toggleFullScreen(nil)` sobre ESA ventana (o se elimina el botón fullscreen y se usa el verde nativo, ver punto 4).
2. **Contenido a pantalla completa de verdad**: mientras `showPlayer`, ocultar toolbar (ya se hace) + `.ignoresSafeArea()` en el contenedor del reproductor (ya está) + verificar `fullSizeContentView` para que el contenido se extienda bajo el titlebar al salir del fullscreen; el layer se ajusta por `layout()` (ya correcto).
3. **Eliminar el `NSPanel` de cerrar** (y su `Task.sleep(300ms)`): la raíz del panel era "los overlays pierden hit-testing tras toggleFullScreen". Fase 2 primero reproduce y aísla esa pérdida de hit-testing con el log 3 (¿los botones reciben click antes/después del fullscreen?); con la ventana correcta + overlay orderado como `.overlay` (ya se hace) el cierre vuelve a ser un botón SwiftUI normal con `.onKeyPress(.escape)`. Si persistiera, solución intermedia aceptable: `NSWindow` del replayer con `styleMask` correcto — NO un panel flotante.
4. **Botón fullscreen**: estado-驱动 — observar `window.styleMask.contains(.fullScreen)` (KVO/notifications) y alternar icono `arrow.up.left.and.arrow.down.right` ↔ `arrow.down.right.and.arrow.up.left`; acción → `window.toggleFullScreen(nil)` sobre la ventana resuelta. Alternativa a evaluar: **quitar el botón** en mac y dejar que el sistema (barra verde + `F`) lo maneje — es el comportamiento más nativo; el overlay solo muestra controles.
5. **Layout por safe area**: sustituir paddings fijos por `GeometryReader`/`safeAreaInsets` del contenedor → controles dentro de límites en notch, externos y Stage Manager; el vídeo con `videoGravity` (ya está) mantiene aspecto.
6. **Evaluar `AVPlayerView`** (AppKit) vía NSViewRepresentable con `controlsStyle = .none`: nos daría el manejo nativo de layer/aspecto/fullscreen/PiP-AirPlay de mac sin reimplementar; mantendríamos overlay propio. Comparar en spike de medio día: si simplifica H2/H4, adoptar; si no, quedarse con el bridge actual (ya correcto en esencia).

**Alternativa descartada salvo que falle 4.7**: ventana dedicada de reproductor (segunda escena `Window`) — arquitectura de reproductores mac (QuickTime/IINA), pero hoy el reproductor vive dentro de la navegación de detalle y cambiarlo afecta a PiP/restore/sheets; considerarla solo si el fullscreen en ventana única no puede eliminarse solapamientos.

### 4.9 Qué EVITAR
- Simular fullscreen (redimensionar ventana a pantalla, ocultar chrome manualmente) → nunca se siente nativo y rompe multi-monitor.
- Más `NSApp.windows.first(where:…)` / por título → fuente de H1.
- Otros `NSPanel`s flotantes para "arreglar" botones.
- `Task.sleep` como sincronización de transiciones (prohibido por constraints).

### 4.10 Riesgos
- La pérdida de hit-testing tras fullscreen es un bug de infraestructura SwiftUI/AppKit: puede requerir spike. Mitigación: reproducir en Fase 0/2.1 ANTES de prometer fechas; fallback = mantener el botón de cierre fuera del overlay con una solución sin panel (p. ej. `NSWindow` content del propio replayer).
- Cambiar la presentación (ZStack ↔ cover) afecta a `onDisappear`/PiP/reporting → tocar solo la capa de ventana, no el ciclo de vida.

### 4.11 Pruebas
Matrix Fullscreen (§12): MacBook, externo, resoluciones, tamaños, entrada/salida ×N, notch, multi-monitor, Stage Manager. Verificar: vídeo llena display, cero solapes (screenshot), controles clicables en todos los estados, Esc cierra, salir restaura ventana exacta.

### 4.12 Criterio de "resuelto"
Entrar/salir de fullscreen es la transición nativa de macOS (misma que el botón verde), el vídeo ocupa el 100% del display, ningún elemento del sistema ni de la app queda visible o superpuesto, y todos los controles siguen operativos antes, durante y después.

---

## 5. Problema 3 — Botones fullscreen y AirPlay (Mac) no funcionan

### 5.1 Síntomas
Iconos presentes en la parte derecha de los controles de Mac, sin efecto al pulsarlos.

### 5.2 Componentes
- Fullscreen: `PlayerView.swift:809-817` (Button) → `:254-259` (`onToggleFullscreen` → keyWindow).
- AirPlay: `PlayerView.swift:846-852` → `AirPlayRoutePicker` (macOS) `:738-780` (`AVRoutePickerView` en `NSViewRepresentable`, delegate con logs `airplay: picker presenting BEGIN/END`).
- Diagnóstico AirPlay ya existente: `AVPlaybackEngine.swift:100` (ext del stream), `:284-306` (KVO `isExternalPlaybackActive`, route changes).

### 5.3 Hipótesis
- **H1 — no llega el evento**: hit-testing roto tras fullscreen (mismo root cause que el panel de cerrar, §4) → el log 3 NO aparecerá al pulsar.
- **H2 — llega pero actúa mal**: fullscreen togglea keyWindow equivocado (H1 de §4); AirPlay abre el sheet pero elegir destino no hace nada porque el stream no es AirPlay-safe (un `.mkv`/`.ts` directo no lo soporta — el propio engine lo loguea en `prepare`) o porque `isExternalPlaybackActive` nunca pasa a true.
- **H3 — AirPlay mac no configurado**: `allowsExternalPlayback = true` está (`AVPlaybackEngine.swift:64`); falta verificar: red local/Bonjour (permiso añadido recientemente), que el `AVRoutePickerView` mac reciba el frame (44×44 con background Circle puede recortar el hit area), y que `prioritizesVideoDevices` no esté disponible/sea inócpo en mac (hoy no se setea en la rama mac — correcto, es iOS-only en la firma).
- **H4 — estado/feedback**: el botón fullscreen no cambia de icono → parece que "no hace nada" aunque sí alterna.

### 5.4 APIs
`AVRoutePickerView` (+ `AVRoutePickerViewDelegate`, `setRoutePickerButtonColor(_:for:)` en mac), `AVPlayer.allowsExternalPlayback`, `AVPlayer.isExternalPlaybackActive` (KVO), `AVPlayer.externalPlaybackActive` video gravity, `AVAudioSession.routeChangeNotification` (iOS), AirPlay 2 receiver discovery (sin entitlement especial para enviar), permisos red local (`NSLocalNetworkUsageDescription` / `NSBonjourServices` — ya en Info.plist).

### 5.5 Flujo esperado (acceptance, del usuario)

```text
Fullscreen: pulsar → transición nativa de macOS → ventana REALMENTE fullscreen →
vídeo ocupa la pantalla → controles se reposicionan → nada se solapa → icono refleja estado.

AirPlay: pulsar → selector de rutas del sistema (AVRoutePickerView) → destinos compatibles →
seleccionar → AVPlayer inicia external playback (log externalPlaybackActive=true) →
vídeo en el receptor → estado del reproductor (controles, Now Playing) se actualiza.
```

### 5.6 Cómo reproducir / diagnosticar
1. Pulsar cada botón con y sin fullscreen activo; capturar log 3 (¿llega?) y log 2 (¿window correcta?).
2. AirPlay con C1 (mp4) y C7 (transcode): ¿`airplay: picker presenting BEGIN`? ¿`externalPlaybackActive=true`? Si BEGIN no aparece → hit-testing/hosting; si aparece pero elegir destino no cambia `externalPlaybackActive` → formato del stream o descubrimiento de receptores.
3. Probar desde iPhone→Apple TV como referencia del mismo servidor/receptor (aisla "problema del Mac" vs "problema del servidor/receptor").

### 5.7 Solución a estudiar
- Se resuelve **junto con la Fase 2** (chrome rediseñado): botón fullscreen estado-driven sobre la ventana resuelta (o eliminado a favor del sistema); AirPlay = `AVRoutePickerView` nativo **mantenido** (es el componente correcto y oficial) pero con hosting saneado (hit area completo, sin Circle recortante encima del área de clicks, sin overlay superior que lo tape).
- Si H2 por formato: garantizar que para AirPlay se entregue una URL AirPlay-safe (el `AVPlayerCapability.chooseURL` ya escoge mp4/HLS; añadir log `airplay: offering <method>` y, si el método es direct-play de contenedor no soportado, ofrecer remux cuando `isExternalPlaybackActive` — evaluar en el spike; no forzar transcode permanente).
- **Decisión "¿controles nativos o custom?"**: para mac se estudiará `AVPlayerView.controlsStyle = .full` como referencia/alternativa — sus botones fullscreen/AirPlay son nativos y funcionan. Recomendación previsible: overlay custom + `AVRoutePickerView` nativo (conserva identidad visual), salvo que el spike muestre que el sistema de hit-testing sigue roto, en cuyo caso `AVPlayerView` con `.none` + overlay encima.

### 5.8 Qué EVITAR
- "Arreglar" el botón metiéndole `simultaneousGesture`/`onTapGesture` encima sin saber si el evento llega.
- Reimplementar un selector de rutas propio (API pública no existe para destinations custom → `AVRoutePickerView` es la oficial).
- Forzar `allowsExternalPlayback` sin verificar formato (silencio total).

### 5.9 Pruebas
Matrix AirPlay (§12): Mac→Apple TV, iPhone→Apple TV, iPhone→Mac (Recepción), con mp4/HLS/transcode, en distintos estados (paused/playing/seek), y verificación de `externalPlaybackActive` en log + estado visual. Fullscreen antes/después del tap.

### 5.10 Criterio de "resuelto"
Los dos botones responden en TODOS los estados (windowed/fullscreen), fullscreen entra de verdad y refleja estado, y elegir un receptor produce reproducción externa real (log + imagen en el receptor).

---

## 6. Problema 4 — Action pill de DetailView → Liquid Glass

### 6.1 Síntoma
La cápsula `.regularMaterial` con iconos (Reproducir/Episodios/check/heart) no encaja con la estética deseada en Mac; se quiere Liquid Glass nativo, coherente con iPhone.

### 6.2 Evidencia actual
- `DetailView.swift:217-251` (`actionPill` + `pillButton`), fondo: `ActionPillBackground` (`:826-845`): en iOS 26 → **sin fondo** (el sistema dibuja su glass de toolbar); en resto (incluido TODO macOS) → `content.background(.regularMaterial, in: Capsule())`.
- En macOS la pill va en un **overlay** `.topTrailing` con `.padding(.top, 60)` (`:57-63`) porque "dentro del toolbar macOS dibuja su propio platter → double pill" (comment `:203-205`) — comportamiento PRE-Liquid Glass; en macOS 26 el platter del sistema ES el efecto deseado.
- **Cómo reproducir/diagnosticar**: screenshot de la pill en (a) macOS 26 actual, (b) macOS 14/15, (c) iOS 26 — comparar con la pill de una app de sistema (App Store/Música) como referencia; si en macOS 26 el toolbar del sistema ya dibuja el glass deseado, la causa es "overlay manual + material casero" y la solución es devolverla al toolbar. Logs: ninguno necesario (es visual; el `#available` branch se verifica compilando ambos).

### 6.3 Hipótesis / decisiones de diseño
- **H1**: en macOS 26+ la forma nativa correcta es **devolver las acciones al `toolbar`** con `ToolbarItem` + `Button`s sin fondo custom → el sistema dibuja Liquid Glass automáticamente y hace morphing con la transición de titlebar (Apple: "aprovechar componentes estándar; evitar fondos personalizados que interfieran con el material").
- **H2**: en macOS 14/15/26 no-available fallback = mantener `.regularMaterial` capsule (actual) o subir a `glassEffect` solo si `#available(macOS 26)`.
- **H3**: en iOS ya está resuelto (`if #available(iOS 26)` sin fondo) — verificar iOS 17-25 (fallback `.regularMaterial` en toolbar: correcto).

### 6.4 Componentes
`DetailView.swift:47-63` (overlay mac), `:202-211` (toolbar), `:217-251`, `:826-845`. Relacionado con Fase 2 (ocultar toolbar al reproducir ya existe).

### 6.5 APIs (a verificar disponibilidad al implementar)
- `Modifier.glassEffect(_:in:)` / `glassEffect(.regular.interactive())` — iOS 26/macOS 26.
- `GlassEffectContainer(spacing:)` + `glassEffectID(_:in:)` — agrupación/morph.
- `ButtonStyle.glass` / `.glassProminent`.
- Toolbar estándar en macOS 26 (glass automático en items), `ToolbarItem`, `.toolbarVisibility`.
- `@Environment(\.accessibilityReduceTransparency)` / Reduce Motion (el sistema ya adapta `glassEffect`; verificar fallback manual).
- Material fallback: `.regularMaterial` (14+).

### 6.6 Solución a estudiar
1. Spike visual en macOS 26: mover `actionPill` de vuelta al `toolbar` y comprobar que el platter del sistema es el glass deseado (sin "double pill"). Si lo es → eliminar `ActionPillBackground` del branch mac-26 y el overlay `.topTrailing`.
2. Si se quiere control total (misma forma capsule con morph), usar `GlassEffectContainer { actionPill.glassEffect(in: .capsule) }` vía `#available(macOS 26.0, *)`.
3. Fallback 14/25: código actual (`.regularMaterial` capsule) — ya es aceptable.
4. Coherencia iPhone: iOS 26 ya usa el glass del sistema — misma acción (toolbar item), cero código nuevo.
5. Extensión opcional (misma fase si hay tiempo): controles del reproductor en mac (círculos `black.opacity(0.5)`) → `.glassEffect(.regular, in: .circle)` con `GlassEffectContainer` agrupando la fila de transporte; SOLO sobre controles (nunca sobre contenido, guía Apple) y condicionado a Fase 2 terminada.

### 6.7 Qué EVITAR
- Blur+transparencia+gradiente+borde recreando glass a mano (ya lo hace `.regularMaterial` — no añadir capas).
- Glass sobre glass (pill de sistema + fondo custom → el "double pill" que ya se vivió).
- Glass en contenido o scrim de vídeo (legibilidad + guía Apple).
- Subir el deployment target para usar `glassEffect` sin availability.

### 6.8 Riesgos
- macOS 26 puede cambiar matices del toolbar glass (beta) → mantener fallback.
- Legibilidad sobre vídeo claro → contrastes del sistema + iconos con peso semibold; probar en matrix Light/Dark/Reduce Transparency.

### 6.9 Pruebas
Matrix Liquid Glass (§12): Light/Dark, Reduce Transparency ON, Reduce Motion ON, tamaños de ventana, vídeo claro/oscuro/movido, macOS 26 vs 14/15 (compile both), iOS 26 vs 17.

### 6.10 Criterio de "resuelto"
La pill de macOS usa glass del sistema (o su fallback) sin doble fondo, idéntica filosofía a iPhone, legible sobre cualquier vídeo, y respeta Reduce Transparency/Motion.

---

## 7. Problema 5 — AirPlay en Lock Screen / Now Playing

### 7.1 Síntoma/deseo
Que el sistema muestre correctamente los controles multimedia en Lock Screen/Control Center (título, progreso, transporte) y acceder a AirPlay desde esa experiencia.

### 7.2 Evidencia actual
- `NowPlaying.swift`: `NowPlayingController` manual — `MPNowPlayingInfoCenter.default().nowPlayingInfo` (title/duration/elapsed/rate/artwork) + `MPRemoteCommandCenter` (play/pause/toggle/skip ±15/seek). Activado por `PlayerViewModel.configureNowPlaying` (`:151-159`), actualizado cada 0.5s (`:513-518`), desactivado en `stopSync` (`:992-996`) con tokens de sesión anti-stale.
- Sesión de audio: `.playback, .moviePlayback` en `ThisJellyFixRootView.configureAudioSession` (`:265-273`).
- **No** se usa `MPNowPlayingSession`.

### 7.3 Qué controla el sistema (importante — no inventar APIs)
- **La Lock Screen la controla el sistema**: `MPNowPlayingInfoCenter` es la API oficial y el sistema decide layout. NO existen APIs públicas para añadir botones custom (incluido AirPlay) a la Lock Screen.
- **El botón AirPlay de Lock Screen/Control Center lo pinta el sistema** cuando: hay sesión Now Playing activa + `AVPlayer.allowsExternalPlayback` + hay rutas de destino disponibles (y, para vídeo, AirPlay activo o elegible). Mecanismo a VERIFICAR en dispositivo (es la hipótesis de integración): publicar Now Playing correctamente + `allowsExternalPlayback=true` (hecho) + audio session activa = el sistema muestra sus controles de ruta.
- En AirPlay activo, la info Now Playing aparece además en la pantalla del Apple TV (documentado por Apple).

### 7.4 APIs implicadas
`MPNowPlayingInfoCenter`, **`MPNowPlayingSession(players:)` (iOS 16+ / macOS 13+ — oficial WWDC22: gestiona Now Playing + remote commands para UNO o VARIOS `AVPlayer`, publicación automática)**, `MPRemoteCommandCenter`, `MPMediaItemProperty*`, `MPNowPlayingInfoProperty*`, `AVAudioSession` (`.playback`), `AVPlayer.allowsExternalPlayback`, `AVRoutePickerView` (in-app), Handoff/CarPlay/Bluetooth (mismos cimientos). Nuevo framework NowPlaying (`MediaSession`, WWDC25+) = investigar disponibilidad vs deployment floor iOS 17.

### 7.5 Hipótesis de las carencias actuales
- **H1**: publicación manual → huecos (falta `MPMediaItemPropertyPlaybackRate` consistente al inicio, artwork asíncrono, y sobre todo: en AirPlay/recivers la info puede no "enganchar" si el rate/elapsed van con retraso del timer).
- **H2**: `MPNowPlayingInfoCenter.default()` vs sesión por-player → con un solo reproductor vale, pero los handlers `MPRemoteCommandCenter` son globales: si la app u otra sesión los toca, los nuestros se pierden (o el lock screen responde a un VM muerto — el diseño de handlers con `[weak self]` y tokens ya mitiga).

**Cómo reproducir / diagnosticar / logs:** reproducir C1 → bloquear pantalla y abrir Control Center → capturar qué aparece (título, arte, progreso, transporte, botón de ruta) y comparar con una app de sistema (TV/Música). Logs a añadir: `np: activate session=<n>` / `np: deactivate` / `np: update t=… rate=…` (permanentes) + los ya existentes `airplay: externalPlaybackActive=…`. Si el lock screen no aparece → revisar orden: `activate` antes de `play`, audio session activa, rate>0. Si aparece info pero NO el botón de ruta → revisar `allowsExternalPlayback` + descubrimiento de receptores (mismo network) → eso confirma que el elemento es del sistema y documentar el hallazgo en `Docs/bugs/`.

### 7.6 Solución a estudiar
1. **Evaluar migración a `MPNowPlayingSession(players: [engine.player])`** en `NowPlayingController`: sesión por VM (no singleton global), su `nowPlayingInfoCenter` para metadata (publicación automática del estado del AVPlayer) y `remoteCommandCenter` para comandos. Ventaja: el sistema refleja exactamente el estado del player (incl. AirPlay) sin nuestro timer. Mantener los comandos extra (skip ±15) vía la sesión.
2. **Completar metadata**: artwork (hecho), `MPMediaItemPropertyAlbumTitle`/series-episode (temporada×episodio), `MPNowPlayingInfoPropertyPlaybackRate` ya OK.
3. **AirPlay Lock Screen**: sin API custom — verificar en C1 con un Apple TV en la misma red que el botón de ruta del sistema aparece en Lock Screen/CC; si no aparece, diagnosticar en orden: (a) ¿Now Playing activo? (b) ¿`isExternalPlaybackActive` al elegir ruta? (c) ¿receptores descubiertos? (logs ya existentes). Documentar el resultado como "esto lo pinta el sistema" en Docs.
4. Reutilizar el mismo `NowPlayingController` en el swap de episodios (Fase 6) para que la metadata cambie sin parpadear (activate con nuevo título conservando sesión).

### 7.7 Qué EVITAR
- Inventar vistas en la Lock Screen (prohibido por plataforma).
- `AVAudioSession` con category equivocada (rompe AirPlay/route).
- Desactivar Now Playing en cada tick o re-registrar comandos por frame (hoy bien: tokens + guard).

### 7.8 Riesgos
- `MPNowPlayingSession` + comandos manuales pueden solaparse → elegir UN dueño de comandos (la sesión) en la migración.
- Cambios en el lock screen afectan a CarPlay/bluetooth → matrix manual.

### 7.9 Pruebas
Matrix AirPlay + bloque Lock Screen (§12): pantalla bloqueada con reproduce/pausa/seek/±15 desde CC y desde Apple TV; artwork/título/progreso correctos; botón de ruta del sistema visible; cambiar de destino actualiza `externalPlaybackActive` y el estado.

### 7.10 Criterio de "resuelto"
Lock Screen/CC muestran título+arte+duración+progreso y responden a transporte; desde ahí se puede enrutar a Apple TV con la UI del sistema; el estado siempre refleja el player real (incl. AirPlay activo).

---

## 8. Problema 6 — Reproducción continua (auto-siguiente estilo Netflix)

### 8.1 Deseo
Final de episodio → detectar → siguiente disponible → preparar → transición → arranque automático; saltar ending si el usuario no hace nada; auto-skip de intro al abrir.

### 8.2 Evidencia actual
- Fin real detectado: `.ended` (`AVPlayerItemDidPlayToEndTime` → `AVPlaybackEngine.swift:344-350` → `PlayerViewModel.handleEngineState:169-172` **solo pone `isPlaying=false` — NO hay auto-avance**).
- Overlay de créditos: `SkipSegmentOverlay` (`PlayerView.swift:1052-1106`) ofrece "Siguiente episodio" y "Saltar ending"; `playNextEpisode()` (`PlayerViewModel:650-653`) solo actúa desde overlay con `activeSegment == .credits`.
- Auto-skip de intro: `SegmentDetector` + `SkipSettings(autoSkip: true, delay 5s)` (`SegmentMarker.swift:69-88`) → **ya activo por defecto si el plugin de segmentos devuelve markers** (intro se salta solo hoy, cuando hay datos).
- Siguiente episodio: `DetailView.nextEpisodeAfter` (`:641-645`, solo la temporada cargada en pantalla) y `DirectPlayer.resolveNextEpisode` (`:174-201`, baja seasons+episodes, solo misma temporada, se resuelve tras montar). **No se usa `/Shows/{id}/NextUp`.**
- Swap in-place: `PlayerView.onChange(of: streamURL)` → `switchToEpisode` (`PlayerViewModel:272-314`) → `resetItemState()` **borra selección de audio/subs y el flag de locked** (`:334-375`) → pérdida de preferencias al cambiar de episodio (reportado).
- Transición: overlay `isSwitchingEpisode` con spinner (`PlayerView:188-207`) — buen punto de partida para la "transición adecuada".
- Preload: no existe. `preferredForwardBufferDuration = 5` (`AVPlaybackEngine:105`).

### 8.3 Hipótesis / huecos
- Sin auto-advance en `.ended` → si el plugin de segmentos NO devuelve credits, el usuario se queda en negro al final.
- Siguiente solo dentro de la temporada → corte en fin de temporada/serie.
- Sin comprobación de disponibilidad → swap a item sin fuente → pantalla de error dentro del player.
- `resetItemState` destruye preferencias → "pierdo idioma/subtítulos".
- Crear un segundo `AVPlayer` para precargar duplicaría memoria/sesión → prohibido por diseño (reutilizar `replaceCurrentItem`).

**Cómo reproducir / diagnosticar / logs:** con C5 (multi-temporada) y C6 (segments) llegar al final de un episodio y observar: ¿dispara `.ended`? (log `engine ENDED item=…`), ¿aparece overlay de crédits? ¿hay `nextEpisode` cableado? (log `ended item=… → next=<id|none reason=…>` de Fase 0). Repetir en fin de temporada, fin de serie y con el plugin de segmentos desactivado (fuerza el camino `.ended` puro). Verificar el reporte: 1 `reportPlayStarted` + N `reportProgress` + 1 `reportStopped` por episodio (logs existentes) y capturar la secuencia antes de tocar nada.

### 8.4 APIs / endpoints
`AVPlayerItemDidPlayToEndTime` (fin real), `AVPlayer.replaceCurrentItem(with:)` (swap sin nuevo player), `AVPlayerItem.preferredForwardBufferDuration`, Jellyfin `GET /Shows/{seriesId}/NextUp?userId` (orden "siguiente visto"), `GET /Shows/{seriesId}/Episodes?seasonId` (orden de temporada, fallback), `POST /Sessions/Playing` reportes (play/progress/stop por episodio), `AVPlayerItem.status/forwardBufferDuration` para precarga.

### 8.5 Diseño de la solución

**Pieza nueva: `NextEpisodeResolver` (ThisJellyFixNetworking, protocolo testeable)**
```swift
public protocol NextEpisodeResolving: Sendable {
    /// Siguiente episodio tras `currentId` en la serie, o nil (fin de serie).
    func nextEpisode(
        userId: String, serverURL: URL, token: String,
        seriesId: String, currentEpisodeId: String, currentSeasonNumber: Int
    ) async throws -> JellyfinEpisode?
}
```
- Implementación: intenta `/Shows/{seriesId}/NextUp` (respeta "lo siguiente según el usuario", cruza temporadas y filtra no disponibles/vistos según parámetros) → fallback: lista de temporada actual (código existente `fetchEpisodes`) y, si es el último de la temporada, baja la siguiente temporada (`fetchSeasons` ya existe) → nil al final de serie.
- Filtra: sin `MediaSources` utilizables (llamada barata a PlaybackInfo o `MediaType`/`HasSomething`) y episodios marcados `played` solo si NextUp lo excluye (política: NextUp es la fuente de verdad).

**Máquina de estados de fin de episodio (en `PlayerViewModel`, reutilizando lo existente)**
```
position ≥ duration - 20  →  (si hay marker .credits) overlay "Siguiente: E{x} — Auto en Ns"
                             (autoSkip ya salta el ending a los 5s si está activo → esto dispara el avance)
.ended (fin real)          →  advanceToNextEpisode()
overlay "Siguiente" manual →  advanceToNextEpisode()
advanceToNextEpisode():
  1. resolver next (si ya cacheado, saltar)  → nil ⇒ estado final (ver "fin de serie")
  2. fetchPlaybackInfo(next) + resolver URL  → fallback a pantalla de error in-player con "Reintentar"
  3. isSwitchingEpisode = true  →  switchToEpisode(url…)   (swap in-place, MISMO AVPlayer)
  4. re-aplicar preferencias de audio/subs (ver carry-over)
  5. isSwitchingEpisode = false, play en 0 (o posición guardada si el server la tiene)
```
- **Umbral "terminado"**: señal primaria = `.ended` (real, ya cableada). Secundaria = `position ≥ duration - 1.5` (mismo umbral de `PiPHandoffPolicy`) para ofrecer el avance si `.ended` no llega (streams que cortan). El reporte `stop` al final marca el episodio como visto según el servidor (Jellyfin aplica su umbral ~90%).
- **Precarga**: resolver `next` + PlaybackInfo/URL **durante los últimos ~30s** (barato: metadata), NO precargar segmentos de vídeo (ancho de banda) y **NUNCA** un segundo `AVPlayer` (memoria). El swap usa el buffer existente (`preferredForwardBufferDuration`).
- **Carry-over de preferencias**: extraer de `resetItemState()` las preferencias de usuario (`selectedAudioTrack`/`selectedSubtitleTrack` como CÓDIGOS de idioma, no índices — los índices cambian por item) y re-aplicarlas tras `loadTracks` del item nuevo, respetando `subtitleSelectionLocked` (si el usuario eligió "Inglés" a mano, el siguiente episodio arranca en Inglés; si eligió "Desactivados", igual). Interactúa con Fase 1 (fuente única): la re-aplicación pasa por `SubtitleSelectionState`.
- **Fin de serie**: mostrar estado final (fotograma actual + "Serie completada" + botón cerrar), NO pantalla negra; reportar stop final.
- **Errores**: fetch/swap fallido → error in-player con "Reintentar" y "Siguiente manual" (sin matar la sesión de reporting del episodio actual hasta que el nuevo arranque).
- **Auto-skip intro**: ya existe (`SkipSettings.autoSkip=true`); verificar con C6 que dispara al abrir; si el plugin no da markers, no inventar (sin timers).
- **Continuidad de sesión de reporting**: `switchToEpisode` ya hace `endCurrentItemSession()` → `reportStopped` + `configureReporting` nuevo → mantener (1 play + 1 stop por episodio).

### 8.6 Componentes
`PlayerViewModel.swift:161-176, 272-375, 640-672, 808-834`; `PlayerView.swift:188-207, 297-312, 1052-1106`; `DirectPlayer.swift:99-201`; `DetailView.swift:573-652`; nuevo `NextEpisodeResolver` + tests.

### 8.7 Qué EVITAR
- `Task.sleep` "para dar tiempo" al final del episodio.
- Crear `AVPlayer`/`AVPlayerItem` por episodio (memory leaks, rebuffer, pérdida de PiP).
- Avanzar sin verificar disponibilidad (pantalla de error en bucle).
- Avanzar en-loop al final de serie.
- Forzar swap cuando el usuario está pausado/scrubando a propósito (gate: solo si `isPlaying` o el overlay fue el desencadenante).

### 8.8 Riesgos
- NextUp devuelve un item de otra temporada/distinto orden → validar con `currentSeasonNumber` y caer al fallback ordenado.
- Doble transición si `.ended` y el marker de créditos disparan a la vez → deduplicar con flag `advanceInProgress` (análogo a `skipInProgress`).
- Quitar el float-PiP (Fase 3) cambia `handleViewExit` — el swap no debe tocar eso (aislar).

### 8.9 Pruebas
- Unit: `NextEpisodeResolver` con stubs (normal, fin de temporada, fin de serie, NextUp caído → fallback, siguiente sin fuente).
- Unit: carry-over de preferencias tras reset (nuevo test en Core/VM).
- Manual matrix Reproducción continua (§12).

### 8.10 Criterio de "resuelto"
Fin de episodio → tarjeta de transición → siguiente arranca solo en ≤2s sin pantalla negra; intro se salta sola; idioma/subs elegidos se mantienen; fin de temporada cruza; fin de serie muestra cierre; errores de red dejan al usuario con opciones; un solo play/stop reportado por episodio.

---

## 9. Problema 7 — PiP automático al salir (iPhone)

### 9.1 Regla decidida
- Salir del reproductor DENTRO de la app (cerrar/cambiar de pantalla) → **cerrar la experiencia, sin PiP** (con reporte de stop).
- Salir de la app (Home/bloqueo) con episodio en marcha → **PiP automático permitido** (idioma Apple).
- Botón PiP manual → se mantiene.

### 9.2 Evidencia actual (dónde se decide hoy)
- Salida del reproductor: `PlayerView.onDisappear` → `viewModel.handleViewExit(handoffAllowed:)` (`PlayerViewModel:1056-1080`) → si `canAutoHandoffToPiP` (`PiPHandoffPolicy.canAutoStart`, `PiPHandoffPolicy.swift:18-41`) **flota a PiP** (`PipCoordinator.float`). ← ESTO es el síntoma.
- Background: `PipCoordinator.configure` fija `canStartPictureInPictureAutomaticallyFromInline = autoStartEnabled` (`PipCoordinator:82-105`), gateado cada 0.5s por la misma política (`PlayerViewModel:538-542`).
- La política vive en Core con tests (`PiPHandoffPolicyTests`).

### 9.3 Hipótesis
- Causa directa = diseño intencional previo ("leaving the player must NOT cut playback" — float al salir). El usuario ahora quiere lo contrario → cambio de POLÍCIA, no de UI.
- Caso borde a vigilar: `PlayerTeardown.errorFlag` (ya evita float tras error) y el "closed by user" de `didStop` (si quitamos float, `floatingVM` casi nunca existirá → simplifica restores).

### 9.4 APIs
`AVPictureInPictureController.canStartPictureInPictureAutomaticallyFromInline` (auto-PiP en background), `AVPictureInPictureController.startPictureInPicture()` (manual), `allowsPictureInPicturePlayback` (AVPlayerViewController — no aplica: usamos controller directo), `AVPlayerView.allowsPictureInPicturePlayback` (sí si se adopta AVPlayerView en Fase 2), delegate `restoreUserInterfaceFor…` (restore), `scenePhase`/UIKit lifecycle, `AVAudioSession` (background audio).

### 9.5 Solución a estudiar
1. **`PiPHandoffPolicy` se divide en dos reglas explícitas** (Core, testeadas):
   ```swift
   /// Salir del reproductor DENTRO de la app → nunca PiP (decisión de producto 2026-10-03).
   public static func canFloatOnViewExit(...) -> Bool { false }
   /// Background/bloqueo con reproducción activa → PiP automático del sistema.
   public static func canAutoStartOnBackground(isPlaying:userPaused:position:duration:engineStopped:hasError:) -> Bool
   ```
   (`canAutoStartOnBackground` = lógica actual de `canAutoStart`; el parámetro `leavingView` desaparece.)
2. `handleViewExit`: quitar el bloque `float(...)` → siempre `stopSync(reportStop: true)` (mantener el guard de error). El VM deja de necesitar `makePipContext` para salida (queda para restore vía `floatingContext` si se mantiene el float de background — verificar si con la regla nueva el float "view-gone" tiene algún caso válido: SI, si el usuario cierra la cover mientras el auto-PiP de background ya arrancó inline… en ese caso el PiP activo NO debe matarse al cerrar → guard: `if PipCoordinator.isActive (windowStarted) → no detener, solo desacoplar`).
3. `canStartPictureInPictureAutomaticallyFromInline` sigue con la política de background (NO tocar el resto).
4. Sustituir los flags estáticos (`PlayerTeardown`, `presentedCount`) por estado inyectado mientras se toca este bloque (riesgo de race documentado en §0) — dentro del alcance de esta fase si es barato; mínimo: documentar invariantes.

### 9.6 Cómo reproducir / verificar
1. Reproducir → cerrar (X o back) → ¿aparece ventana flotante? (hoy SÍ = bug) → tras fix: NO; audio para; `reportStopped` enviado (log).
2. Reproducir → Home → ¿PiP? (debe SÍ) → volver → restore fullscreen.
3. Reproducir → pausar → Home → ¿PiP? (NO, política userPaused).
4. Reproducir → error de red → salir → ¿PiP? (NO).
5. Botón PiP manual → flota → X → cierra sesión.

### 9.7 Qué EVITAR
- "Arreglar" poniendo `canStartPictureInPictureAutomaticallyFromInline = false` global → rompe el PiP de background que sí se quiere.
- Eliminar `AVPictureInPictureController` → pierde PiP manual.
- Dejar `float()` accesible sin gate → regresión futura silenciosa.

### 9.8 Riesgos
- Romper el restore/`PipLayerHostView` (el root depende de `floatingContext`): si `float()` deja de llamarse desde salida, el flujo de restore por tap-sobre-ventana sigue vivo para el PiP de background — testear la matriz completa.
- Cerrar con `stopSync` mientras hay PiP activo (caso borde 2) → guard explícito + test manual.

### 9.9 Pruebas
Matrix PiP (§12) completa + unit tests de las dos funciones de política (sustituyen/estén junto a `PiPHandoffPolicyTests`).

### 9.10 Criterio de "resuelto"
Salir del reproductor dentro de la app JAMÁS abre PiP (con o sin reproducción en marcha, con o sin error); salir de la app con episodio en marcha SÍ abre PiP; manual sigue funcionando; restore y reporting intactos.

---

## 10. Compatibilidad multiplataforma (req. 9)

| Área | iPhone | iPad | Mac | Apple TV |
|---|---|---|---|---|
| Subtítulos (P1) | invariante única fuente (nativo/overlay) | igual | igual | nativo = estilo canónico; overlay compartido; verificar con Siri Remote picker |
| Fullscreen (P2) | fullScreenCover ya nativo | igual + multitarea (popover no debe romper presentación) | rediseño ventana (Fase 2) | sin fullscreen (tvOS = siempre pantalla completa); sin cambios |
| Botones/AirPlay (P3) | AVRoutePickerView iOS ya funciona → solo regresión | igual | fix chrome | tvOS NO emite AirPlay (es receptor); sin botón |
| Liquid Glass (P4) | toolbar iOS 26 (ya) / fallback 17 | igual | `#available(macOS 26)` + fallback 14+ | toolbar tvOS: glass del sistema si existe; no forzar |
| Lock Screen (P5) | MPNowPlayingSession + CC + CarPlay | igual | menu bar / Control Center | Now Playing propio de tvOS (Siri Remote top sheet) — verificar que `MPNowPlayingInfoCenter` no pisa |
| Continuidad (P6) | swap in-place compartido | igual | igual (mismo `PlayerView`) | foco en botón "Siguiente"; auto-advance idéntico |
| PiP (P7) | política nueva | PiP nativo de iPad (multitarea) — mantener manual | nativo de macOS (evaluar en Fase 2 con AVPlayerView) | no existe PiP |

visionOS (existe en proyecto): compila, sin alcance explícito; verificar builds.

---

## 11. Matriz de testing (req. 11)

**Unit (`swift test`)** — targets existentes Core/Playback/Networking:
- Subtítulos: `SubtitleSelectionState` invariante, dedupe embebido/externo, `SRTParser` (ya), perfil `SubtitleProfiles` (ya).
- PiP: `PiPHandoffPolicy` — vista saliente (siempre false) vs background (matriz isPlaying/userPaused/ended/error).
- Continuidad: `NextEpisodeResolver` (6 casos §8.9), carry-over de preferencias, umbral de fin.
- Player: `AVPlaybackEngineTests` (ya) — añadir: deselect forzado tras prepare, apply-out-of-range.

**Manual — subtítulos:** SRT · ASS/SSA · WebVTT · forzados · externos · embebidos · Direct Play · Direct Stream · Transcoding → siempre UNA capa.
**Manual — fullscreen mac:** MacBook · externo · resoluciones · tamaños · entrada/salida ×5 · notch · multi-monitor · Stage Manager → sin solapes, controles clicables.
**Manual — AirPlay:** iPhone→Apple TV · iPhone→Mac(Recepción) · Mac→Apple TV · estados paused/playing/seek · mp4/HLS/transcode · desde Lock Screen.
**Manual — continuidad:** normal→siguiente · fin de temporada · fin de serie · siguiente no disponible · error de red · cambio de subs · cambio de idioma · contenido con transcode · intro auto-skip · ending auto-skip.
**Manual — PiP:** salir del reproductor (NO PiP) · Home (PiP) · bloquear (PiP) · cambiar de app · volver/restore · manual on/off · pausado+Home (NO PiP).
**Manual — Liquid Glass:** Light · Dark · Reduce Transparency · Reduce Motion · tamaños de ventana · vídeo claro/oscuro/movido · macOS 26 y fallback.

---

## 12. Anti-patrones globales (EVITAR — req. 8/resultado)

1. Ocultar visualmente una capa sin saber quién la pinta (subtítulos).
2. Timers/delays como sincronización (`Task.sleep(300ms)` ya existe en el panel mac — se elimina, no se copia).
3. Heurísticas de ventana (`NSApp.keyWindow`, `windows.first`, buscar por título).
4. Más ventanas/paneles flotantes para parchear hit-testing.
5. Blur/gradientes caseros en vez de `glassEffect`/materiales del sistema.
6. Un `AVPlayer` por episodio/preload (memoria, rebuffer, PiP roto).
7. Cambios de UI que rompan el ciclo de vida de sesión (reporting/NowPlaying/PiP) sin tocar los tests de política.
8. Subir deployment targets para usar APIs nuevas sin `#available`.
9. Solucionar un problema de una plataforma asumiendo que vale para las 4 (p. ej. fullscreen no existe en iOS/tvOS igual).

---

## 13. Criterios globales de aceptación (req. resultado esperado)

1. **Subtítulos**: una sola capa, todo formato, todo método, 4 plataformas; log sin violaciones.
2. **Fullscreen Mac**: transición nativa real, vídeo 100% pantalla, cero solapes, controles operativos, salida limpia.
3. **Botones Mac**: fullscreen estado-driven + AirPlay con selección de rutas que realmente enruta (log `externalPlaybackActive=true`).
4. **Pill**: Liquid Glass del sistema en macOS 26, fallback limpio, coherente con iOS.
5. **Lock Screen**: metadata+transporte correctos, ruta AirPlay del sistema visible y funcional (documentando qué es del sistema).
6. **Continuación**: auto-advance con transición ≤2s, sin perder idioma/subs, fin de serie/serie/errores cubiertos, un solo reporte por episodio.
7. **PiP**: salir dentro de la app = nunca PiP; salir de la app = PiP; manual OK.
8. `swift test` verde en las 4 plataformas; sin dependencias nuevas; sin hacks de timer/heurística.

---

## 14. Desglose de tareas por fase (checklist de ejecución)

### Fase 0 — Instrumentación (§2)
- [ ] 0.1 Corpus C1-C7 + notas de reproducción
- [ ] 0.2 Logs 1-5 (commit `chore(player): diagnostic logging`)
- [ ] 0.3 Baseline síntomas (screenshots+logs) en `Docs/bugs/`
- [ ] 0.4 Build 4 targets + `swift test` verde

### Fase 1 — Subtítulos (§3)
- [ ] 1.1 Repro corpus + log → identificar QUÉ capa es "fondo negro" y cuál "sin fondo" (decisión con usuario)
- [ ] 1.2 `SubtitleSelectionState` en Core + tests (failing primero)
- [ ] 1.3 Engine: exclusividad dura (re-assert + KVO `currentMediaSelection` con fallback a tick) + log de reversión
- [ ] 1.4 VM: dedupe embebido/externo + guard de burn-in (Encode) + tests
- [ ] 1.5 Unificar estilo según decisión de 1.1 (`AVTextStyleRule` si gana el nativo)
- [ ] 1.6 Matrix manual §11 subtítulos + `swift test` + commit `fix(subtitles): single render source`

### Fase 2 — Chrome macOS (§4/§5)
- [ ] 2.1 Spike hit-testing: reproducir pérdida tras toggleFullScreen con logs 2-3; documentar causa raíz
- [ ] 2.2 Resolver ventana del replayer (view.window del representable); fullscreen sobre ESA ventana; log permanente styleMask
- [ ] 2.3 Eliminar `CloseButtonWindowRepresentable` (NSPanel+sleep) → botón SwiftUI de cierre + Esc
- [ ] 2.4 Controles por safe area/GeometryReader (quitar paddings fijos)
- [ ] 2.5 Botón fullscreen estado-driven (o eliminación a favor del sistema — decisión en 2.1)
- [ ] 2.6 AirPlay: hosting saneado + verificación `externalPlaybackActive` + spike `AVPlayerView` (½ día, decisión documentada)
- [ ] 2.7 Matrix fullscreen + AirPlay (§11) + commits por task

### Fase 3 — PiP (§7)
- [ ] 3.1 Tests nuevos de política (view-exit=false, background=actual) → failing
- [ ] 3.2 `PiPHandoffPolicy` split + `handleViewExit` sin float + guard PiP-activo
- [ ] 3.3 Matrix PiP (§11) + `PiPHandoffPolicyTests` + commit `fix(pip): no auto-PiP on in-app exit`

### Fase 4 — Liquid Glass (§6)
- [ ] 4.1 Spike macOS 26: toolbar nativa vs `glassEffect(in: .capsule)` (capturas)
- [ ] 4.2 Implementar rama `#available(macOS 26)` + fallback 14/25 (compilar ambos)
- [ ] 4.3 (Opcional) controles del replayer mac → glass, si Fase 2 está estable
- [ ] 4.4 Matrix visual §11 + commit `feat(design): native Liquid Glass action pill on macOS`

### Fase 5 — Lock Screen/AirPlay (§7-5)
- [ ] 5.1 Spike `MPNowPlayingSession(players:)` vs manual (comandos duplicados = criterio de decisión)
- [ ] 5.2 Migrar `NowPlayingController` a la sesión elegida + metadata completa (serie/episodio)
- [ ] 5.3 Verificar en dispositivo botón de ruta del sistema en Lock Screen/CC; documentar "qué pinta el sistema"
- [ ] 5.4 Matrix Lock Screen/AirPlay + commit `feat(nowplaying): MPNowPlayingSession integration`

### Fase 6 — Reproducción continua (§8)
- [ ] 6.1 `NextEpisodeResolver` + protocolo + tests stubs (failing primero)
- [ ] 6.2 Cablear triggers: `.ended` + overlay créditos + umbral duration-1.5 + flag anti-doble
- [ ] 6.3 Carry-over de preferencias de audio/subs por idioma + tests
- [ ] 6.4 Precarga de URL a ~30s + transición `isSwitchingEpisode` + fin de serie
- [ ] 6.5 Errores (fetch/swap) con reintento manual
- [ ] 6.6 Matrix continuidad (§11) + `swift test` + commit `feat(playback): auto-advance next episode`

---

*Plan de investigación y solución — nada de lo anterior se implementa hasta ejecutar cada fase con su paso de diagnóstico primero.*
