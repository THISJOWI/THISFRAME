# Plan técnico de investigación y optimización de rendimiento — ThisJellyFix

**Fecha:** 2026-10-03
**Alcance:** Cliente Jellyfin multiplataforma (iPhone, iPad, Mac, Apple TV, visionOS). Swift 5.10, SwiftUI, SwiftPM sin dependencias externas.
**Naturaleza:** documento de investigación/hoja de ruta. **No contiene cambios de código.** Toda evidencia es path:line del código actual.

---

## Resumen ejecutivo

Auditoría de las cinco áreas del paquete (`Core`, `Networking`, `Discovery`, `Playback`, `Feature`) + puntos de entrada de las 5 apps. Hallazgos dominantes:

1. **El primer frame llega tarde por Keychain síncrono**: ~15 operaciones iCloud-Keychain antes del primer render, y `KeychainStore()` se construye *dentro* del `body` raíz → 6 lecturas extra por re-render (`ThisJellyFixRootView.swift:332,89`, `KeychainStore.swift:49,151-178`).
2. **No existe ninguna caché de datos Jellyfin** (ni memoria, ni disco, ni ETag) → cada entrada a Home/Detail refaz la red completa (`JellyfinLibraryClient.swift`, `DetailView.swift:725-738`).
3. **El pipeline de imágenes decodifica en MainActor** con tareas no cancelables → jank de scroll directo (`ImageView.swift:48,71,81`).
4. **`TJFLog` compila 3 regex por línea + hace I/O de disco síncrono en el hilo llamante**, incluida la ruta del timer de reproducción (`Logging.swift:25-46,68-79`).
5. **Cascadas secuenciales**: 7 round-trips TMDB seriales en Discovery (`DiscoveryLoader.swift:50-78`), 3-4 peticiones seriales por detalle (`DetailView.swift:717-791`), `markAvailable` re-codifica el historial entero por ítem (`DownloadCoordinator.swift:283-294,317-320`).
6. **Playback penaliza el time-to-first-frame**: `prepare()` espera a cargar pistas antes de reproducir, seeks de tolerancia cero en el resume, doble apertura de asset (`AVPlaybackEngine.swift:102-153`).
7. **Actualizaciones SwiftUI gruesas**: Home re-renderiza completo ante cualquier fila que cambie; PlayerView re-evalúa su body completo a 2 Hz; Keychain se lee dentro de `body`.

Con estas correcciones la app puede pasar de "funcional" a **sensación inmediata** (métricas objetivo en §10).

---

## 1. Áreas de investigación

| # | Área | Archivos clave |
|---|------|----------------|
| A | Arranque y primera pintura | `Apps/*`, `ThisJellyFixRootView.swift`, `KeychainStore.swift`, `AuthModel.swift` |
| B | Caché, persistencia y sincronización | ausencia total de cache layer; `UserDefaults`, Spotlight, Handoff |
| C | Red y API Jellyfin | `ThisJellyFixNetworking/*` |
| D | Pipeline de imágenes | `ImageView.swift`, `LibraryModel.swift` (image URLs) |
| E | Renderizado SwiftUI, listas y estado | `HomeView`, `DetailView`, `MediaCardView`, `SearchView` |
| F | Navegación y transiciones | `ThisJellyFixRootView`, `HomeView` (macOS split), covers |
| G | Playback: arranque, buffering, Direct Play | `AVPlaybackEngine`, `StreamURLResolver`, `JellyfinPlaybackClient`, `PlaybackDeviceProfile` |
| H | Playback: CPU, timers, subtítulos, Now Playing | `PlayerViewModel`, `PlayerView`, `NowPlaying`, `PipCoordinator` |
| I | Discovery y metadatos externos (TMDB/*arr) | `DiscoveryLoader`, `CatalogRecommender`, `TMDBMetadataProvider`, `ArrClients` |
| J | Descargas (cola *arr) | `DownloadCoordinator`, `DownloadQueue`, `DiscoveryModel` |
| K | Concurrencia y memoria | todo `Sources/` |
| L | Logging y diagnóstico | `Logging.swift` |
| M | Background/foreground, energía y restauración | `scenePhase`, `HandoffActivity`, ausencia de BG tasks |
| N | Efectos visuales (Liquid Glass, sombras, animaciones) | `MediaCardView`, `DetailView`, root |

---

## 2-6. Problemas potenciales → detección → herramientas → optimizaciones → impacto

### A. Arranque y primera pintura

**Problemas potenciales (evidencia):**
- `ServerConnectionModel()` + `AuthModel()` ejecutan **~15 `SecItemCopyMatching` sincrónicos en main** antes del primer frame, muchos con `kSecAttrSynchronizable = true` (round-trip al demonio de iCloud Keychain, cientos de ms en lanzamiento frío) — `ThisJellyFixRootView.swift:13,482-493`, `AuthModel.swift:24-43`, `KeychainStore.swift:37,74-78`.
- `KeychainStore()` instanciado **dentro del `body`** → 6 ops Keychain por cada re-render del root — `ThisJellyFixRootView.swift:332,89`.
- `migrateIfNeeded()` corre en cada init de `KeychainStore` (5 sondeos extra) — `KeychainStore.swift:151-178`.
- Doble restore de sesión (init + `.task { restoreSession }`) — `ThisJellyFixRootView.swift:162-166`.
- `onAppear` del root arranca `NWBrowser` 2,5 s en main + registra handlers PiP — `ThisJellyFixRootView.swift:156-160,278-314`, `LocalNetworkAuthorizer.swift:36-55`.
- `DiscoveryModel.live` construye `IntegrationConfig` + `DownloadCoordinator.hydrate()` (decode JSON) dentro de `loadLibrary` — `DiscoveryModel.swift:67-81`.

**Cómo detectar/medir:** signposts `os_signpost` alrededor de init de modelos, `ScenePhase` → primer `.onAppear` de Home; Instruments **Time Profiler** en lanzamiento frío (ver qué símbolos dominan los primeros 500 ms); **App Launch** template / `XCTest` de lanzamiento con métrica `kActivityStartToFirstFrame` de Xcode Test Plans; `MXMetricManager` → `MXAppRunMetric` (tiempo de lanzamiento en dispositivos reales).

**Herramientas Apple:** Instruments (Time Profiler, os_signpost), Xcode Organizer (launch regressions por versión), MetricKit (`MXAppRunMetric`, `MXDiagnosticPayload.hangDiagnostics`), `kdebug`/`swift run` no aplica → consola con `os_signpost` instrument.

**Optimizaciones:**
- Memoizar credenciales en memoria: una única lectura al arrancar; `KeychainStore` como singleton/actor con caché y `migrateIfNeeded()` solo una vez por proceso.
- Sacar `KeychainStore()` del `body` (crear en init del modelo raíz, inyectar).
- Pintar Home con datos cacheados y hidratar en segundo plano (el diseño ya publica `LibraryModel` antes de `load()`, mantenerlo).
- Deferir NWBrowser/PiP registration a después del primer frame (`.task` con prioridad `.utility`).
- Lecturas críticas sin `synchronizable` (el token no necesita iCloud-sync en cada read).

**Impacto potencial:** alto. Lanzamiento frío percibido de ~1 s a <300 ms; elimina micro-stutters en el primer scroll (Keychain en main). Relación esfuerzo/impacto excelente (P0).

---

### B. Caché, persistencia y sincronización

**Problemas potenciales:**
- **Cero caché de respuestas Jellyfin** (grep `SwiftData|CoreData|URLCache|cachesDirectory` → nada en `Sources/`). Cada navegación re-fetch: resume en cada entrada a Home (`HomeView.swift:293-297`), detalle+PlaybackInfo en cada push (`DetailView.swift:725-738`), favoritos en cada switch de pestaña (`FavoritesView.swift:75`).
- `fetchResumeItems` usa `.reloadIgnoringLocalCacheData` — nunca aprovecha caché HTTP — `JellyfinLibraryClient.swift:156-161`.
- Sin ETag/If-Modified-Since en todo el repo (0 hits).
- Imágenes: solo `NSCache` en memoria, `totalCostLimit = 100MB` **inerte** porque `setObject` no pasa `cost:`; evicciona solo por `countLimit = 200`; sin capa disco — `ImageView.swift:11-24`.
- URLs de imagen sin tag de versión (`imageTags` ya decodificados pero no usados) → arte obsoleto + sin cache-busting — `LibraryModel.swift:259-264`.
- Spotlight: **reindex completo** en cada `load()` (incluido pull-to-refresh), mapping con `Calendar.current` por ítem en MainActor — `LibraryModel.swift:142`, `SpotlightIndexer.swift:27-72`.
- Historial de descargas: `persist()` = encode JSON completo + `UserDefaults.set` **tras cada mutación**, y `markAvailable` se llama en bucle por cada ítem de biblioteca → O(n) encodes durante la carga de Home — `DownloadCoordinator.swift:317-320,283-294`, `DiscoveryModel.swift:154-159`.
- Sin `beginBackgroundTask`/`BGTaskScheduler` en `Sources/` (la doc dice que existe para PiP; gap doc↔código — `Docs/bugs/2026-09-25-investigation.md:236`).

**Cómo detectar/medir:** Network Instruments (conteo de peticiones por navegación), `URLCache` hit-rate propio con signposts, Allocations (picos de `Data`), Tests: contador de llamadas mock por sesión de navegación típica.

**Herramientas:** Instruments **Network**, **Allocations**, os_signpost, Xcode Organizer (HTTP en tiempo real para métricas de red).

**Optimizaciones:**
- Capa de caché de respuestas: memoria NSCache con TTL corto (30-60 s) + caché disco opcional (Caches directory) con invalidación por `DataChanged`/versión de servidor; claves por (endpoint + params + userId).
- Stale-while-revalidate: mostrar caché al instante y revalidar en background → **sensación Netflix** (la sección aparece ya poblada).
- Coalescing de peticiones en vuelo (mapa in-flight por clave) → elimina duplicados de `force:true`, múltiples triggers de resume y mounts simultáneos.
- ETags (`If-None-Match`) para endpoints de lista; añadir `fields`/`enableImages=false` para reducir payloads.
- `cost:` real en NSCache (bytes decodificados) + capa disco LRU para pósters (evita re-descarga en cada sesión).
- Spotlight incremental (diff por id) y off-main.
- `persist()` batch: debounce de 1 s o al final del lote; `markAvailable` en un solo encode.

**Impacto potencial:** muy alto. Reduce peticiones por sesión típica 60-80 %, navegación instantánea con caché, datos en Home en frío desde disco. P0.

---

### C. Red y API Jellyfin

**Problemas potenciales:**
- **Sin paginación** y `TotalRecordCount` ni siquiera decodificado (`JellyfinLibraryClient.swift:6-11`) — límites fijos 20/30/40 ocultan contenido (funcional) y impiden scroll infinito futuro.
- `fetchItems` sin `Recursive=true` ni `fields` en raíz → payloads más grandes de lo necesario (`JellyfinLibraryClient.swift:74-90`).
- **N+1 por detalle**: hasta 4 peticiones por tap de tarjeta; `DirectPlayer` hace detail→seasons→episodes **seriales** para el siguiente episodio (`DetailView.swift:725-791`, `DirectPlayer.swift:180-194`).
- **Sin coalescing ni caché**: cada push re-fetch detalle + PlaybackInfo; la detail dispara además un segundo PlaybackInfo **sin DeviceProfile** solo para chips (`DetailView.swift:725-730`).
- `force:true` del resume salta el cooldown desde ≥5 sitios (`HomeView.swift:34,134,159,331`, `ThisJellyFixRootView.swift:146,154,322`).
- Búsqueda usa `/Items?searchTerm` en vez de `/SearchHints` (más barato en servidor) (`JellyfinLibraryClient.swift:126-143`); cada tecla aceptada = 2 llamadas (librería + TMDB catálogo) (`SearchView.swift:166-195`); bug: `isSearching` puede quedarse en `true` (`SearchView.swift:163,174-182`).
- Auth header reconstruido por petición con **lectura síncrona de Keychain** (`DeviceIdentifier().current()`) sin memoizar (`JellyfinLibraryClient.swift:181`, `DeviceIdentifier.swift:11-17`).
- `URLSession.shared` puro: sin config, timeouts inconsistentes (auth = 60 s default), **sin prioridades**, sin límite de concurrencia por host → API, imágenes, TMDB y *arr comparten el pool de 6 conexiones.
- Sin retry/backoff, sin `NWPathMonitor`, sin refresh de 401 (solo flag) (`LibraryModel.swift:231-241`).
- Cuerpos de respuesta convertidos a `String` y registrados con regex en el hilo llamante (resume completo, PlaybackInfo 800 chars, cada POST de progreso) — `JellyfinLibraryClient.swift:164-166`, `JellyfinPlaybackClient.swift:60,246-258`.

**Cómo detectar/medir:** Instruments Network (waterfall por navegación: peticiones, bytes, tiempo hasta último byte); signpost por endpoint; contar peticiones en una sesión guiada (arrancar → Home → detalle → play → volver).

**Herramientas:** Network Instruments, `URLSessionTaskMetrics` (tiempos de conexión/TLS/DNS por petición), Xcode Organizer Network requests timing, Charles/mitmproxy opcional (no Apple).

**Optimizaciones:**
- Caché + coalescing (§B) — aquí el mayor efecto.
- Paralelizar detalle: `async let` de detail+PlaybackInfo+seasons+episodes donde no hay dependencia; reutilizar la misma respuesta PlaybackInfo para chips y reproducción (con perfil).
- Prefetch de detalle en el **press** de la tarjeta (inicio de la descarga durante la animación de transición).
- Cambiar a `/SearchHints`, añadir debounce ya presente pero dedupe de query en vuelo.
- Memoizar `DeviceIdentifier`; decoder compartido (static).
- `URLSessionConfiguration` propia: `timeoutIntervalForRequest` corto (10-15 s coherente), `httpMaximumConnectionsPerHost` diferenciado (API prioritaria), `URLCache` con `requestCachePolicy` y tamaño explícito; **prioridad `URLSessionTask.priority`** para API > imágenes visibles > prefetch > TMDB.
- Retry con backoff exponencial para 5xx/timeouts (1-2 reintentos), `NWPathMonitor` para degradación offline elegante.
- Logging de cuerpos solo en DEBUG o con muestreo.

**Impacto potencial:** muy alto en percepción (detalle abre en un round-trip), medio en bytes. P0/P1.

---

### D. Pipeline de imágenes

**Problemas potenciales:**
- **`CachedImageLoader` es `@MainActor` → `PlatformImage(data:)` (decode JPEG 1600px en detalle) corre en main durante el scroll** — `ImageView.swift:48,71-81`, `DetailView.swift:302-307`. Causa nº1 de jank de scroll.
- **Tarea inner `Task {}` no cancelable**: el scroll rápido dispara descargas que siguen vivas fuera de pantalla; `cancel()` es código muerto (`ImageView.swift:71-97,117-119`).
- Sin dedupe de vuelo: mismo ítem en 2 filas = 2 descargas (`ImageView.swift:59-67`).
- Sin prefetch (ningún `prefetchDataSource`/equivalente) → el primer pintado de una fila es siempre fetch (`ImageView.swift:168`, grep `prefetch` → nada).
- Sin downsampling al tamaño objetivo: backdrop 1600×900 RGBA dibujado en ~600 pt (sobremuestreo 2,7-4× GPU+memoria) (`LibraryModel.swift:262-264`, `DetailView.swift:305`).
- `NSCache` sin cost → evicción ineficaz; en macOS `NSImage.lockFocus` (main) en path muerto (`ImageView.swift:14-24,30-41`).
- Sin transición placeholder→imagen (pop-in duro) (`ImageView.swift:148-166`).

**Cómo detectar/medir:** Instruments **Time Profiler** durante scroll de Home (buscar `PlatformImage.init`/`CGImage` en main thread) + **SwiftUI/Animation Hitches** (Core Animation hitches); Allocations durante scroll; signpost `image_decode` con duración.

**Herramientas:** Time Profiler, Core Animation (hitches/ FPS), SwiftUI template, Allocations.

**Optimizaciones:**
- Decode + resize en `Task.detached(qos: .userInitiated)` o usando `CGImageSourceCreateThumbnailAtIndex` con `kCGImageSourceCreateThumbnailFromImageAlways` + `kCGImageSourceThumbnailMaxPixelSize` (decode directo al tamaño objetivo, ahorra decode completo + resize).
- Cancelación real: pasar `Task`/`withTaskCancellationHandler`, respetar `Task.isCancelled` tras cada await; llamar a `cancel()` en `onDisappear`.
- Dedupe in-flight (mapa URL→Task) + caché disco por URL con `?tag=` de `imageTags` para invalidación.
- Prefetch de la ventana visible ±1 fila con prioridad `.utility` (diferente de la imagen en pantalla, `.userInitiated`).
- Transición de opacidad 150 ms (percepción de "instantáneo").

**Impacto potencial:** muy alto en scroll smoothness (el efecto más visible en día a día). P0.

---

### E. Renderizado SwiftUI, listas y estado

**Problemas potenciales:**
- **Tracking grueso de Home**: el body de Home lee `rows`, `isLoading`, `errorMessage`, `sessionExpired`, `pendingNavigationItem`, `discovery.*`, `coordinator.entries` → cualquier mutación (una fila de resume, un tick de descargas a los 30 s) re-renderiza Home completo con NavigationStack y destinos (`HomeView.swift:20-60,196-283`).
- **Keychain dentro de `body`**: Home lee `discovery.hasDownloadService` → 2 `SecItemCopyMatching` por render; root lee token/usuario por render (`HomeView.swift:209`, `ThisJellyFixRootView.swift:332-334`, `IntegrationConfig.swift:101-108`).
- **Escritura por tecla en Ajustes**: `.onChange` de claves API → 3 Keychain writes + 2 UserDefaults + `reloadConfiguration()` + task de red **por carácter** (`IntegrationsSection.swift:57-61,218-228`).
- **Bug de inyección**: `IntegrationsSection` usa `@EnvironmentObject` pero se inyecta `.environment(...)` (Observation) → runtime error o UI que nunca se actualiza (`IntegrationsSection.swift:16` vs `ThisJellyFixRootView.swift:84,97`).
- `DiscoveryModel` es a la vez `@Observable` y `ObservableObject` (doble maquinaria) (`DiscoveryModel.swift:12-13`).
- **DetailView con 24 `@State`**: cualquier toggle re-evalúa el body completo con GeometryReader + FlowLayout (`DetailView.swift:12-43`).
- **macOS `.id(selectedTab)`** destruye/reconstruye el NavigationStack de detalle en cada click de sidebar (`HomeView.swift:99-102,124`).
- `ScrollView`+`VStack` no-lazy en Home (filas eager); `ForEach(Array(rows.enumerated()))` reconstruye tuplas por body (`HomeView.swift:196-283,260`).
- `allItems` (flatMap+dedup) se recalcula en **cada acceso**: cada search, cada poll de 30 s, cada handoff (`LibraryModel.swift:31-34`).
- Búsqueda: 40 tarjetas con `.transition(scale+opacity)` en un solo `withAnimation(.spring)` → ráfaga de 40 springs (`SearchView.swift:90-99,175-177`).
- Tarjetas: sombra por tarjeta + doble `clipShape` + spring con delay aleatorio en entrada (muchas animaciones concurrentes al hacer scroll) (`MediaCardView.swift:26,58,95-101`).
- Favoritos no propagan del Detail a FavoritesView (refetch por mount) (`DetailView.swift:656-677`, `FavoritesView.swift:75`).
- Spotlight mapping síncrono en MainActor al final de cada `load()` (`LibraryModel.swift:142`).

**Cómo detectar/medir:** Instruments **SwiftUI** (View Body / Body size), Time Profiler (conteo de `body` invocaciones), signposts alrededor de mutaciones; Xcode **View Body count** en debug; debug de "Implicit Animation" en Core Animation.

**Herramientas:** SwiftUI instrument, Time Profiler, Core Animation Hitches, `os_signpost`.

**Optimizaciones:**
- Partir Home en subvistas con `@Observable` props acotadas (fila de resume como propio estado; descargas solo en `DownloadsButton`/`DownloadsView`); evitar que el root lea Keychain.
- Mover I/O fuera de `body` a init/task; cachear `hasDownloadService`/usuario en el modelo.
- Debounce de guardado en Ajustes (0,5 s) o guardar al perder foco.
- Corregir `@EnvironmentObject` → `@Environment(DiscoveryModel.self)` (bug funcional además de perf).
- Eliminar `.id(selectedTab)` en macOS (usar `NavigationStack` por split con estado propio, no reconstrucción).
- Memoizar `allItems` (invalidar en `didSet` de `rows`) e índice de librería para `CatalogRecommender` (actualmente O(n·m) con `caseInsensitiveCompare`, ~40k compares por load — `CatalogRecommender.swift:82-84`).
- Animaciones: una sola animación de entrada por fila (no por tarjeta), delay escalonado por índice visible, o quitar animación de entrada tras el primer load.
- Reducir springs de búsqueda a opacidad; partir `DetailView` en subvistas pequeñas (Hero, Actions, InfoChips, Episodes) para acotar invalidaciones.
- Sombra una vez en la fila, no por tarjeta; evaluar `drawingGroup()` solo donde midas mejora.
- `ForEach` sobre `Identifiable` directo, sin `enumerated()`.

**Impacto potencial:** alto (menos re-renders = scroll + transiciones fluidas). P0/P1.

---

### F. Navegación y transiciones

**Problemas potenciales:**
- Push de detalle sin prefetch: 3-4 RTT + decode 1600px en main antes del primer pintazco (`DetailView.swift:717-791`).
- `navigationDestination` re-registrado por body → posibles re-inits de DetailView (`.task` re-fire → fetch duplicado) (`HomeView.swift:26-43,126-143`).
- `fullScreenCover` del player construye `PlayerViewModel`+`AVPlayer`+`AVPlayerLayer`+KVO **en `PlayerView.init`**, que se ejecuta en cada render del padre aunque SwiftUI descarte el state (`PlayerView.swift:111-114`, `DirectPlayer.swift:51-67`) — coste alto en cada transición que toca el cover.
- Perfil: `NavigationStack` anidado dentro de `ScrollView` (300 pt fijo) con FavoritesView con su propio stack → coste extra de layout + back roto (`ProfileView.swift:12,36`, `FavoritesView.swift:29`).
- macOS: destrucción total por `.id(selectedTab)` (§E).

**Cómo detectar/medir:** signposts `nav_push_start/end` midiendo tiempo hasta primer frame del detail; SwiftUI instrument durante navegación.

**Optimizaciones:**
- Prefetch detail en `onPressGesture`/`simultaneousGesture` (o al menos backdrop + detail con `async let`) mientras corre la transición.
- Lazy init del VM del player (patrón `State` con factory, o crear el player al abrir el cover, no en init del view).
- Un solo stack por plataforma: en Perfil, eliminar el stack anidado.
- Coalescer fetch de detalle (§C) → navegación back/forward instantánea.

**Impacto potencial:** alto en "sensación de apertura de contenido" (el objetivo premium). P0.

---

### G. Playback: arranque, buffering, Direct Play/Transcode

**Problemas potenciales:**
- **`prepare()` awaits `loadTracks` antes de retornar** → `play()` se gatingea en cargar grupos de pistas (`AVPlaybackEngine.swift:112-113`; `PlayerView.swift:156-169`).
- **Seeks de tolerancia cero** en resume y ±15 s → en MP4 progresivo puede decodificar desde el inicio (`AVPlaybackEngine.swift:148-153`).
- **Doble apertura de asset**: `AVPlayerItem(url:)` + `AVURLAsset` separado para pistas → contenedor parseado 2 veces (`AVPlaybackEngine.swift:102,112`).
- **Sin `preferredPeakBitRate` ni `automaticallyWaitsToMinimizeStalling` explícito**; `MaxStaticBitrate = 140 Mbps` (sin cap real) (`PlaybackDeviceProfile.swift:124-125`); `preferredForwardBufferDuration = 5` agresivo sin techo de bitrate → riesgo de rebuffer en 4K remoto (`AVPlaybackEngine.swift:105`).
- Segunda llamada a PlaybackInfo **sin DeviceProfile** solo para chips de detail → decisión de transcodificación duplicada en servidor (`DetailView.swift:725-730,748-751`).
- Fallback del ladder con `static=true` **se salta la decisión del servidor** (puede fallar con mkv/DTS en vez de reintentar HLS) (`StreamURLResolver.swift:73-79,100-106`).
- `PlayMethod` resultante se descarta → **sin telemetría** de qué se usa realmente (Direct Play vs Transcode) (`StreamURLResolver.swift:69-70`).
- `MediaSource` no decodifica `SupportsDirectPlay/DirectStream` → el cliente re-adivina lo que el servidor ya decidió (`PlaybackInfo.swift:25-33`).
- **Sin precarga del siguiente episodio** (3 GETs seriales de metadatos + PlaybackInfo frío en el swap) (`DirectPlayer.swift:174-201`).
- Sin perfil de dispositivo por plataforma (mismo profile en tvOS/iOS/macOS) (`DirectPlayer.swift:109`, `DetailView.swift:586`).
- Estado `.buffering` emitido por el engine y **ignorado** por el VM → sin spinner de buffering (UX de congelación) (`PlayerViewModel.swift:173-175`).
- tvOS **sin seek bar** (el `DragGesture` está compilado out sin sustituto focusable) (`PlayerView.swift:983-997`).

**Cómo detectar/medir:** signposts `ttff_prepare` (tapped play → primer frame), Instruments **Video**/OpenGL ES (o Metal System Trace) para dropped frames; medir `timeControlReason`/`loadedTimeRanges` vía KVO de diagnóstico; contar rebuffers con `AVPlayerItemFailedToPlayToEndTime`/stalls; logs de `PlayMethod` (a añadir como métrica).

**Herramientas:** Metal System Trace, Video template, Network (mientras se reproduce: bitrate real vs cap), MetricKit `MXCPUMetric`/`MXCellularConditionMetric` en campo.

**Optimizaciones:**
- No gatear `play()` en `loadTracks`: empezar reproducción y cargar selección de pistas en paralelo (aplicar al llegar).
- Un solo asset compartido entre `AVPlayerItem` y lectura de pistas.
- Seeks tolerantes (p. ej. 1-2 s) para resume/salto; tolerancia cero solo al hacer scrub exacto.
- `preferredPeakBitRate` acorde a la red (perfil por plataforma y por condición de red); reevaluar `preferredForwardBufferDuration` con techo de bitrate.
- Reutilizar la respuesta PlaybackInfo (con perfil) entre chips y play; añadir `SupportsDirectPlay/DirectStream` al decode y usar el `PlayMethod` del servidor con fallback local.
- **Precarga del siguiente episodio durante los créditos**: prefetch metadata + PlaybackInfo + `AVPlayerItem` en `automaticallyWaitsToMinimizeStalling` → swap instantáneo (efecto "Netflix").
- Registrar y subir `PlayMethod`, TTFF y rebuffer count como métricas (ver §10).
- Spinner de buffering reactivo al estado real; scrub bar focusable en tvOS.
- Perfil de dispositivo específico por plataforma (tvOS: red cableada/hdmi, caps distintos).

**Impacto potencial:** muy alto en la sensación de "empieza al instante" y en experiencia premium de reproducción. P0 (TTFF) / P1 (resto).

---

### H. Playback: CPU, timers, subtítulos, Now Playing, PiP

**Problemas potenciales:**
- **Timer de 0,5 s lanza un `Task` no guardado por tick**; si el cuerpo tarda >0,5 s (red) los ticks se solapan → trabajo duplicado (`PlayerViewModel.swift:497-498`).
- `loadSegmentsIfNeeded` puede **apilar peticiones** por solapamiento (`PlayerViewModel.swift:591-610`).
- **Sin `deinit` en `PlayerViewModel`**: si `stopUpdating` no corre, el Timer de 0,5 s queda vivo para siempre (`PlayerViewModel.swift:88,497`).
- **`subtitleText` se asigna incondicionalmente** cada tick → invalidación de `@Observable` → **body completo de PlayerView (9 overlays + 3 sheets) se re-evalúa 2 veces/s** aunque nada cambie (`PlayerViewModel.swift:483-489,510`; `PlayerView.swift:231-245`).
- `MPNowPlayingInfoCenter` reescrito **cada 0,5 s** (dict completo) (`PlayerViewModel.swift:514-518`); `setAutoStartEnabled` llamado cada tick (`PlayerViewModel.swift:538-542`); `SkipSettings.current()` = 4 UserDefaults por tick (`PlayerViewModel.swift:616`).
- Subtítulos externos: SRT descargado una vez y buscado por binsearch — bien — pero la descarga corre dentro del tick y los primeros ticks bloquean en red (`PlayerViewModel.swift:840-891`); descarga de subs **secuencial** por stream (`PlayerViewModel.swift:851-859`).
- `TJFLog` en la ruta del timer (diagnósticos primeros 10 ticks; reporte de progreso cada 10 s con cuerpos) — regex+I/O en main (`PlayerViewModel.swift:533-536,933`).
- Doble hop de estado KVO → `DispatchQueue.main` → `Task { @MainActor }` (`AVPlaybackEngine.swift:409-418`).
- `DownloadCoordinator` sin `@MainActor` mutando estado observable desde executor genérico (`DownloadCoordinator.swift:29-31`).

**Cómo detectar/medir:** Time Profiler durante 5 min de reproducción (ver % en `PlayerViewModel.tick`, `TJFLog`, SwiftUI body); Swift Concurrency instrument (actividad del main actor); Allocations (creación de String/Dictionary por tick).

**Optimizaciones:**
- Guardar el Task del tick y cancelarlo antes de relanzar (o usar un solo `Task` con `AsyncTimerSequence`); dedupe de fetch de segmentos.
- Asignar `subtitleText`/`currentTime`/etc. **solo si cambió** (comparación previa); aislar el reloj en subvista pequeña para que el body grande no se invalide 2 Hz (el HUD de tiempo puede usar `TimelineView(.periodic)`).
- NowPlaying: actualizar 1 Hz o solo en cambios de estado; `setAutoStartEnabled` solo en cambios reales; cachear `SkipSettings`.
- `deinit { stopUpdating() }` en el VM.
- Descarga de subs en `TaskGroup`, fuera del tick.
- Migrar `TJFLog` a `os.Logger` con niveles y privacidad (§L).
- `DownloadCoordinator` → `@MainActor` o actor.

**Impacto potencial:** medio-alto en CPU durante reproducción y en batería/temperatura; alto en fluidez de la UI del reproductor. P1.

---

### I. Discovery y metadatos externos

**Problemas potenciales:**
- **7 round-trips TMDB seriales** (trending series → trending movies → 5 seeds en bucle `for await`) → la fila "Para ti" tarda 7×RTT; sin `TaskGroup` (`DiscoveryLoader.swift:50-52,75-78`).
- TMDB y *arr usan `.reloadIgnoringLocalCacheData` (siempre bytes completos), sin backoff ni manejo de 429 (`TMDBMetadataProvider.swift:90`, `ArrClients.swift:158-159`).
- `provider` computado relee Keychain 2× por acceso (`DiscoveryLoader.swift:16-22`).
- `CatalogRecommender.buildRows`: índice de librería reconstruido **4 veces** por llamada + filter O(n·m) con `caseInsensitiveCompare` (`CatalogRecommender.swift:71-85`).
- Búsqueda dispara TMDB en paralelo con librería (2 llamadas por keystroke aceptado) (`SearchView.swift:166-195`).

**Cómo detectar/medir:** Network waterfall en carga de Home (ver la cascada); signpost `discovery_load`.

**Optimizaciones:**
- `withTaskGroup` para los 7 llamados (o limitar seeds concurrentes a 3); cachear respuestas TMDB (URLCache con TTL de horas — son datos "trending" que cambian poco).
- Índice de títulos `Set<String>` lowercase una sola vez por build.
- Memoizar provider.
- Mantener orden de llamadas si el test `DiscoveryLoaderTests.swift:34` lo pinnea (actualizar test si se paraleliza).

**Impacto potencial:** medio (fila "Para ti" aparece 5-7× antes en conexiones lentas). P1.

---

### J. Descargas (cola *arr)

**Problemas potenciales:**
- `refreshDownloads` **sin guard de reentrada** y disparado por `.task` de cada `DiscoveryRowView` mientras `entries.isEmpty` → hasta 6 refrescos concurrentes al montar Home (≈12 peticiones *arr + 6× storm de `markAvailable`) (`DiscoveryRowView.swift:41-46`, `DownloadsButton.swift:40-45`, `DiscoveryModel.swift:130-133`).
- `persist()` por cada mutación + `markAvailable` en bucle por ítem (§B).
- `refresh()` Radarr→Sonarr serial (podría ser `async let`) (`DownloadCoordinator.swift:198-211`).
- `removeEntries` hace un `lookup` por entrada (`DownloadCoordinator.swift:246-252`).
- `submit()` sin guard anti doble-tap (doble envío al *arr) (`DownloadCoordinator.swift:75-104`).
- Poll de 30 s muta `coordinator.entries` → re-render de todas las filas Discovery + botón (`DiscoveryModel.swift:137-150`).

**Optimizaciones:** guard único de reentrada; refresco global único al montar Home (no por fila); batch persist; `async let` para Radarr+Sonarr; anti doble-submit; acotar la observación (que solo `DownloadsView` y el botón lean `entries`; las filas lean un `Set<ID>` derivado estable).

**Impacto potencial:** medio (ráfaga de red y CPU al abrir Home). P1.

---

### K. Concurrencia y memoria (transversal)

**Problemas potenciales:**
- `Task {}` fire-and-forget sin padre en ~20 sitios (detalle, progreso, refresh, imagen) → sin cancelación ni back-pressure (`DetailView.swift:662,685`, `PlayerViewModel.swift:902,934,959`, `ThisJellyFixRootView.swift:105,146,154,322`…).
- Sin QoS: descargas de imagen y fetch de biblioteca a prioridad default → compiten con el render del scroll.
- Retenciones: handlers PiP con `[self]` de por vida en statics del root (`ThisJellyFixRootView.swift:30-31,278-314`); `PipCoordinator.floatingVM` retenido si nunca se restaura (`PipCoordinator.swift:53-54`); `PlayerView.init` crea VM+AVPlayer cada render (churn, no leak).
- `NowPlayingController` `@unchecked Sendable` con mutable sin aislar (`NowPlaying.swift:16,30-33`).
- Búsqueda de handoff lineal sobre `allItems` ×2 (`ThisJellyFixRootView.swift:448,457`).

**Cómo detectar/medir:** Instruments **Leaks** y **Allocations** (pico de VMs/AVPlayer en navegación), Swift Concurrency instrument (saltos de actor, work en main), Time Profiler.

**Optimizaciones:** envolver trabajos en estructuras con padre (`.task` de la vista o `Task` guardado); QoS `.userInitiated` para datos visibles, `.utility` para prefetch/poll; auditar estáticos retenedores; `Sendable` correcto en `NowPlayingController`.

**Impacto potencial:** medio (higiene, evita picos y fugas latentes). P1/P2.

---

### L. Logging y diagnóstico

**Problemas potenciales:**
- `TJFLog` es `func` con `String` → **la interpolación siempre se evalúa** (111 call-sites), sin nivel, sin `#if DEBUG` (`Logging.swift:11-15`).
- Por línea: 3 `NSRegularExpression` compiladas desde cero + `print` + stat de fichero + `fopen/fwrite/fclose` **síncrono en el hilo llamante** (incluido main durante reproducción) (`Logging.swift:25-46,68-79`).
- Cuerpos de respuesta completos stringificados en rutas calientes (resume, PlaybackInfo, progreso).

**Optimizaciones:** migrar a `os.Logger` (compilación estática de formato, niveles, `privacy: .private`, integración con Console/Instruments), o precompilar regex una vez + I/O asíncrono en cola de fondo + gate de nivel; eliminar `String(data:)` de cuerpos en release.

**Impacto potencial:** medio-alto en CPU de rutas calientes (especialmente reproducción), y ganancia de diagnóstico real en producción vía Console. P0 (rápido y transversal).

---

### M. Background/foreground, energía y restauración

**Problemas potenciales:**
- Un solo observador de `scenePhase` (`.active → refreshResume`) en root; sin manejo de `.inactive/.background` (pausar polls, tareas) (`ThisJellyFixRootView.swift:22,149-155`).
- Sin `beginBackgroundTask` para el reporte de progreso al salir a background (puede cortarse a mitad) y sin `BGTaskScheduler`.
- Sin restauración de escena más allá de Handoff (NSUserActivity).
- Poll de descargas de 30 s correcto (se detiene en idle) pero corre también con la app en background si el task sobrevive (verificar).
- `LocalNetworkAuthorizer` NWBrowser de 2,5 s en cada prompt de Perfil.

**Optimizaciones:** pausar poll/timers en `.background`; `beginBackgroundTask` breve para `Sessions/Stopped` + progreso final; persistir el estado de navegación (restauración de stack) para que volver del background sea instantáneo sin re-fetch (combinado con caché §B); métricas energéticas.

**Herramientas:** Energy Log instrument, MetricKit (`MXCPUMetric`, `MXDisplayMetric`), Xcode Organizer battery/hang metrics.

**Impacto potencial:** medio (batería + sensación de continuidad). P1/P2.

---

### N. Efectos visuales y Liquid Glass

**Problemas potenciales:**
- Sombra + doble clip por tarjeta en grids densos; sin medida todavía (§E).
- Springs con delay aleatorio por tarjeta en la primera carga (`MediaCardView.swift:95-101`).
- Gradiente de fondo compuesto siempre detrás del root (`ThisJellyFixRootView.swift:70-75`).
- Materiales (`.regularMaterial` / Liquid Glass de sistema) están como overlays estáticos fuera del scroll — bajo riesgo actual; vigilar al añadir glass dentro de celdas.
- Animaciones de entrada de búsqueda (40 springs simultáneos).

**Cómo detectar/medir:** Core Animation **Color Offscreen-Rendered** (amarillo = sombras/blur offscreen), FPS/hitches durante scroll con `Animation Hitches`.

**Optimizaciones:** sombras una vez por sección o `compositingGroup`; animaciones de entrada por fila, una sola vez; evaluación empírica de `drawingGroup()`; mantener glass fuera de contenido scrollable o medirlo en dispositivos base.

**Impacto potencial:** medio en GPUs débiles (iPhone SE/Apple TV). P1/P2.

---

## 7. Priorización

| Prioridad | Ítem | Área | Impacto | Esfuerzo |
|---|---|---|---|---|
| **P0** | Decode de imágenes off-main + cancelación + downsample | D | Muy alto | Medio |
| **P0** | Caché de respuestas Jellyfin + coalescing + stale-while-revalidate | B/C | Muy alto | Alto |
| **P0** | Keychain memoizado y fuera de `body`; primer frame sin I/O sincrónico | A | Alto | Bajo |
| **P0** | `TJFLog` → `os.Logger` con niveles | L | Medio-alto | Bajo |
| **P0** | Playback TTFF: no gatear play en tracks + seek tolerante + un solo asset | G | Muy alto | Medio |
| **P0** | Prefetch de detalle en el tap + paralelizar fetch del detail | F/C | Alto | Medio |
| **P0** | Bug `@EnvironmentObject`/`.environment` (funcional) | E | Alto | Muy bajo |
| **P1** | Tracking fino de vistas (partir Home/DetailView, sacar Keychain de body) | E | Alto | Medio |
| **P1** | Precarga del siguiente episodio | G | Alto (UX) | Medio |
| **P1** | Discovery en `TaskGroup` + caché TMDB | I | Medio | Bajo |
| **P1** | Descargas: guard reentrada, batch persist, acotar observación | J | Medio | Bajo |
| **P1** | Player: asignar estado solo al cambio, 1 Hz NowPlaying, deinit timer | H | Medio | Bajo |
| **P1** | Prioridades/QoS de URLSession + config propia | C | Medio | Bajo |
| **P1** | Animaciones/sombras de tarjetas (medir → reducir) | N | Medio | Bajo |
| **P2** | Paginación + `TotalRecordCount` + `/SearchHints` | C | Alto (escala) | Medio |
| **P2** | Spotlight incremental | B | Bajo-medio | Bajo |
| **P2** | Restauración de escena + background tasks | M | Medio | Medio |
| **P2** | Perfil de dispositivo por plataforma + telemetría `PlayMethod` | G | Medio | Medio |
| **P2** | macOS sin `.id(selectedTab)`, Perfil sin stack anidado | F | Medio | Medio |

---

## 8. Cambios duales: rendimiento + experiencia premium

| Cambio | Rendimiento | Experiencia |
|---|---|---|
| Caché + stale-while-revalidate | −70 % peticiones | Home/detalle **aparecen ya poblados** (sensación Netflix) |
| Prefetch en el tap + transición con datos | −TTFT percibido | Abrir contenido = transición instantánea |
| Precarga del siguiente episodio | −1 RTT + asset frío | Autoplay sin pantalla negra |
| Imágenes off-main + fade-in | scroll a 60 fps sin hitches | "Snap" de pósters, pop-in suave |
| Keychain cacheado | primer frame <300 ms | Arranque instantáneo |
| Animación de entrada única por fila | menos trabajo de composición | Motion cuidado, no caótico |
| Spinner de buffering reactivo + TTFF bajo | — | Reproductor "fiable" percibido |
| `os.Logger` | CPU en rutas calientes | Diagnóstico profesional en campo |

---

## 9. Plan de pruebas por dispositivo

| Dispositivo | Foco específico | Configuración de prueba |
|---|---|---|
| **iPhone (gama baja actual)** | Scroll de Home, TTFF de vídeo, lanzamiento frío, térmica | iPhone SE o el más lento soportado (iOS 17); Red condicionada (3G/High Latency); modo Low Power |
| **iPhone/iPad (gama alta)** | Hitches de transiciones, Liquid Glass, 120 Hz ProMotion (dónde se ve el jank) | Dispositivo con ProMotion; Energy instruments con pantalla 120 Hz |
| **iPad** | Stage Manager/multiventana (`UIScreen.main.bounds` en `heroHeight` es incorrecto — `DetailView.swift:798-812`), split, tamaño de grid grande | iPad con multitarea; layouts column+detail (NavigationSplitView) |
| **Mac** | `.id(selectedTab)` teardown, rendimiento de ventana, cursor/trackpad,材料as en AppKit | macOS 14 base; profiling con Allocations durante uso largo |
| **Apple TV** | Focus + scroll de listas grandes, tiempo de arranque del reproductor, sin seek bar (gap), red cableada vs Wi-Fi, memoria (256 MB-1 GB) | Apple TV real (no solo simulador); TV 4K; probar bibliotecas grandes |
| **Todos** | Biblioteca grande (2k-10k ítems): spam de filas, Spotlight, búsqueda | Servidor de prueba con biblioteca grande; medir `Users/Items` payload |

Criterios de salida por dispositivo: 60 fps sostenido en scroll (hitches < 1 por s), lanzamiento < 1 s en frío, TTFF de vídeo < 2 s en LAN.

---

## 10. Métricas y benchmarks

### 10.1 Instrumentación previa (baseline antes de tocar nada)
1. Signposts (`os_signpost`) en: `launch → first_frame`, `home_load`, `detail_tap → detail_visible`, `play_tap → first_frame`, `image_fetch`, `discovery_load`. Interfaz `OSSignposter` con nombres estables.
2. Contadores por sesión: nº peticiones HTTP, bytes descargados, cache hit-rate, `PlayMethod` (Direct Play/Stream/Transcode), rebuffer count.
3. Escenarios de benchmark repetibles (test UI o script de guion):
   - `S1` Lanzamiento frío → primer frame Home (×10, mediana).
   - `S2` Home completo (todas las filas + discovery) (×10).
   - `S3` Tap tarjeta → detail visible + backdrop (×10).
   - `S4` Tap play → primer frame de vídeo (×10).
   - `S5` Scroll Home 30 s (medir hitches/FPS).
   - `S6` Búsqueda con 10 keystrokes (peticiones, latencia).
   - `S7` Volver de background → UI reactiva.

### 10.2 Métricas objetivo (targets)

| Métrica | Baseline (a medir) | Objetivo |
|---|---|---|
| Tiempo a primer frame (frío) | medir | < 500 ms (target ideal < 300 ms) |
| Home completo tras primer frame | medir | < 800 ms LAN / < 1,5 s WAN |
| Tap → detail visible (con caché) | medir | < 300 ms |
| Tap → detail visible (sin caché) | medir | < 1 RTT + 200 ms |
| Play → primer frame | medir | < 2 s LAN, < 3 s WAN |
| Scroll FPS | medir | 60 (120 en ProMotion) fps, hitches < 1/s |
| Peticiones por sesión S1-S7 | medir | −70 % tras caché/coalescing |
| % tiempo main actor en scroll | medir | < 15 % en Time Profiler |
| Tiempo de CPU medio durante 30 min play | medir | −30 % (log/tick fixes) |
| Memoria residente en Home | medir | < 150 MB (incluye caché imágenes con cost real) |
| Crash/hang rate | Xcode Organizer | 0 hangs > 700 ms (MetricKit) |
| Lanzamiento (p50 en campo) | MetricKit `MXAppRunMetric` | regresiones < 10 % release a release |

### 10.3 Herramientas Apple por fase
- **Fase baseline:** Instruments Time Profiler, Network, Allocations, SwiftUI, Energy; signposts; test plans con métricas de lanzamiento.
- **Fase correctiva:** Core Animation (hitches, offscreen), Swift Concurrency (actividad del main actor), Metal System Trace (video).
- **Fase de campo:** MetricKit (`MXMetricManager`: launch, CPU, memoria, hangs, luminancia), Xcode Organizer (CPU/memoria/hangs/anr por dispositivo y versión), Console.app con subsistemas `os_logger`.
- **Regresiones:** tests UI con umbrales en CI (peticiones por escenario, hit-rate de caché), comparación de baseline por release.

---

## 11. Fases de ejecución (hoja de ruta)

1. **Fase 0 — Medición (1-2 días):** signposts + baseline de S1-S7 en dispositivo base y Apple TV. Sin cambios funcionales.
2. **Fase 1 — P0 rápidos (2-4 días):** Keychain memoizado/fuera de body, `os.Logger`, bug `@EnvironmentObject`, decode off-main con cancelación, guards de descargas.
3. **Fase 2 — Caché y red (1 semana):** capa de caché + coalescing + prefetch de detail + URLSession config/prioridades.
4. **Fase 3 — Playback TTFF (3-5 días):** prepare sin gate, seeks tolerantes, asset único, telemetría `PlayMethod`, spinner de buffering.
5. **Fase 4 — Render y estado (1 semana):** partir Home/DetailView, tracking fino, animaciones/sombras, macOS split.
6. **Fase 5 — UX premium (1 semana):** stale-while-revalidate, precarga de episodio siguiente, fade-in de imágenes, transiciones.
7. **Fase 6 — Escala y campo (continuo):** paginación, Spotlight incremental, background/restauración, MetricKit/Organizer como rutina.

Cada fase cierra con re-medición de S1-S7 contra la baseline de la Fase 0.

---

## Apéndice — hallazgos positivos (conservar)

- Filas de biblioteca en paralelo con publicación incremental progresiva (`LibraryModel.swift:99-137`).
- Identidades estables de filas/tarjetas → conservan estado de loader (`LibraryModel.swift:6-21`).
- Cooldown de 5 s en refresh de resume (aunque `force` lo salta) (`LibraryModel.swift:185-226`).
- Búsqueda con debounce 300 ms, cancelación y guards (`SearchView.swift:150-197`).
- Decodificación JSON fuera del main (clientes nonisolated).
- Subtítulos externos: descarga única + binary search; embebidos vía `AVMediaSelection` nativo.
- Limpieza correcta de observers/timers en `AVPlaybackEngine.deinit` y `PlayerView.onDisappear`.
- Poll de descargas se auto-detiene en reposo.
- Cero dependencias externas: todas las optimizaciones son nativas (URLCache, os.Logger, CGImageSource, MetricKit, signposts).
