# Outline "falsos resueltos" — Implementation Plan

> **For agentic workers:** implement task-by-task, TDD, one commit per task.

**Goal:** Cerrar los 7 huecos reales que quedan en items de la nota de Outline marcados como "Corregido en `<commit>`" pero que NO funcionan en el código.

**Architecture:** Todos los cambios son locales a un módulo. Lógica pura nueva en `ThisJellyFixCore` (testeable en `swift test`); UI en `ThisJellyFixFeature`; Cast en `ThisJellyFixCast` (solo iOS, sin target de test → se verifica compilando el scheme iOS).

**Tech Stack:** Swift 5.10, SwiftUI, AVFoundation, Google Cast SDK 4.8.6, XCTest (SwiftPM, host macOS).

**Spec:** nota de Outline "Reporte de problemas y mejoras" (colección THISFRAME, doc `87871c14-1312-4abd-b2ac-0040c438c729`).

## Global Constraints

- `swift build` / `swift test` = host macOS, solo módulos compartidos. NO cubre `#if os(iOS)`.
- Tras tocar código condicional de plataforma: `xcodebuild -project thisjellyfix.xcodeproj -scheme thisjellyfix-iOS build`.
- Solo se edita `project.yml` + `xcodegen`; nunca `project.pbxproj` a mano.
- Design tokens: `MareaTheme`. Sin dependencias nuevas.
- Tokens en Keychain, nunca logueados (`TJFLog` redacta).
- Cast: import solo vía `canImport`; el target que enlaza `GoogleCastStatic` necesita `-ObjC` (ya en `project.yml`).

## Review Focus

- Un refresh de biblioteca donde UNA petición falla no puede vaciar un estante que antes tenía contenido.
- Ningún `navigationDestination(for:)` duplicado para el mismo tipo dentro del MISMO `NavigationStack`.
- El salto configurado (10–90 s) debe valer igual en botón, swipe, doble toque y lock-screen/mando.
- El avance automático a episodio siguiente solo puede dispararse UNA vez por fin de episodio.
- Un dispositivo Cast que aparece tarde (o que no dispara callback del SDK) debe verse igual sin pulsar "Reintentar".

---

### Task 1: Retry de Cast que nunca repuebla la lista

**Files:**
- Modify: `Sources/ThisJellyFixCast/CastManager.swift` (`restartDiscovery`, `reloadDevices`)
- Modify: `Sources/ThisJellyFixCast/CastController.swift` (`devices`)

**Interfaces:**
- Produce: `CastManager.refreshDevices()` público; `CastController.devices` pasa a `@Published public private(set) var devices: [CastDevice]`.

- [ ] **Step 1**: En `CastManager.restartDiscovery()`: reinstallar el listener si `!isDiscoveryListenerInstalled`, y llamar `reloadDevices()` al final.
- [ ] **Step 2**: Añadir `public func refreshDevices()` que llame a `reloadDevices()`.
- [ ] **Step 3**: En `CastController`: sustituir el `devices` calculado por `@Published public private(set) var devices: [CastDevice] = []`, asignado en `syncFromManager()` desde `manager.devices`.
- [ ] **Step 4**: En `CastDevicePickerSheet`, polear `controller.refreshDevices()` cada 2 s mientras la hoja está visible (un Chromecast que aparece sin callback del SDK debe verse igual).
- [ ] **Step 5**: `xcodebuild -scheme thisjellyfix-iOS build`.

---

### Task 2: Serie borrada sigue en la app

**Files:**
- Modify: `Sources/ThisJellyFixFeature/LibraryGridView.swift`
- Modify: `Sources/ThisJellyFixFeature/RootView.swift`
- Modify: `Sources/ThisJellyFixFeature/LibraryModel.swift`
- Test: `Tests/ThisJellyFixFeatureTests/LibraryModelDeletionTests.swift`

- [ ] **Step 1**: Test que falla — `testFailedRowKeepsItsShelfOnRefresh`: la fila "Series" sigue presente tras un refresh donde esa petición falla.
- [ ] **Step 2**: En `LibraryModel`, al fallar el fetch de una fila durante un refresh, republicar la fila previa (mismo título) para que el buffer la conserve.
- [ ] **Step 3**: En `LibraryGridView`, recargar todas las páginas cargadas al volver a `.active` (`@Environment(\.scenePhase)`).
- [ ] **Step 4**: En `RootView`, sacar el handler de `scenePhase` del bloque `#if os(iOS)` para que macOS/tvOS también recarguen.
- [ ] **Step 5**: `swift test --filter LibraryModelDeletionTests`.

---

### Task 3: Destino duplicado `JellyfinMediaItem`

**Files:**
- Modify: `Sources/ThisJellyFixFeature/LibraryGridView.swift`

- [ ] **Step 1**: Sustituir `NavigationLink(value: item)` por `NavigationLink { DetailView(...) } label: { ... }` y eliminar el `.navigationDestination(for: JellyfinMediaItem.self)` del grid (el stack anfitrión ya lo registra; dos registros del mismo tipo en un stack son ambiguos → push que no empuja y vuelve atrás).
- [ ] **Step 2**: `swift build`.

---

### Task 4: El salto del lock-screen ignora la configuración

**Files:**
- Modify: `Sources/ThisJellyFixPlayback/NowPlaying.swift`
- Modify: `Sources/ThisJellyFixFeature/PlayerViewModel.swift`
- Modify: `Sources/ThisJellyFixFeature/PlayerView.swift`
- Test: `Tests/ThisJellyFixFeatureTests/PlayerViewModelTransportIntentTests.swift`

- [ ] **Step 1**: Test que falla — el skip remoto usa `PlaybackJumpSettings.current()`.
- [ ] **Step 2**: En `NowPlayingController`, leer `PlaybackJumpSettings.current()` para `preferredIntervals` y exponer `refreshSkipIntervals()`.
- [ ] **Step 3**: En `PlayerViewModel.init`, `np.onSkipBackward/onSkipForward` usan la distancia configurada.
- [ ] **Step 4**: En `PlayerView`, `.onChange` de los valores de salto → `viewModel.refreshTransportPreferences()`.
- [ ] **Step 5**: `swift test --filter PlayerViewModelTransportIntentTests`.

---

### Task 5: La barra de duración no se acorta

**Files:**
- Modify: `Sources/ThisJellyFixFeature/PlayerView.swift`

- [ ] **Step 1**: Limitar el ancho de la barra de seek (`maxWidth` + centrado) para que sea visiblemente más corta que la fila de controles.
- [ ] **Step 2**: `swift build`.

---

### Task 6: Fin de episodio no avanza al siguiente

**Files:**
- Modify: `Sources/ThisJellyFixFeature/PlayerViewModel.swift`
- Test: `Tests/ThisJellyFixFeatureTests/PlayerViewModelCompletionTests.swift`

- [ ] **Step 1**: Test que falla — con `hasNextEpisode = true`, `.ended` dispara `onPlayNextEpisode` exactamente una vez.
- [ ] **Step 2**: En `handleEngineState(.ended)`, tras `finishCurrentItem()`, avanzar al siguiente episodio si lo hay.
- [ ] **Step 3**: `swift test --filter PlayerViewModelCompletionTests`.

---

### Task 7: Buffering sin señal en pantalla + destello de intención en Cast

**Files:**
- Modify: `Sources/ThisJellyFixFeature/PlayerView.swift`
- Modify: `Sources/ThisJellyFixFeature/PlayerViewModel.swift`
- Test: `Tests/ThisJellyFixFeatureTests/PlayerViewModelTransportIntentTests.swift`

- [ ] **Step 1**: Test que falla — el estado del receptor no pisa la intención local de pausa mientras el receptor va por detrás.
- [ ] **Step 2**: En `PlayerViewModel`,.intención de cast (`castIntentPaused`) que el mirror del receptor no puede sobrescribir hasta que el receptor confirm.
- [ ] **Step 3**: En `PlayerView`, overlay con `ProgressView` cuando `viewModel.isBuffering`.
- [ ] **Step 4**: `swift test`.

---

### Task 8: Actualizar la nota de Outline

- [ ] **Step 1**: Marcar como resueltos solo los items verificados; dejar pendientes los que siguen sin resolver (widget, 4K móvil, listas con títulos fuera del servidor, item de TMDB en Buscar, botón de refrescar biblioteca, Favoritos como lista,，统一 de nombres).
- [ ] **Step 2**: Reetiquetar los items cuya nota de "Corregido en `<commit>`" describía un arreglo incompleto.
