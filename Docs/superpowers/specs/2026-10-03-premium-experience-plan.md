# Plan de mejora premium — ThisJellyfix ("La Marea")

**Fecha:** 2026-10-03
**Objetivo:** Elevar la app cliente de Jellyfin a una sensación *premium* con estética inspirada en Apple TV / Apple Music: minimalista, oscura, contenido protagonista — nativa en tvOS, macOS, iPad e iPhone. Sin dependencias de terceros (se mantiene la filosofía hand-rolled).

**Alcance acordado:**
- Premium primero: UI/UX y pulido. Funciones de catálogo grandes (offline, música, Live TV, perfiles) solo como mención de roadmap (bloque 8).
- Las 4 plataformas son primera clase (tvOS, macOS, iOS/iPadOS, visionOS).
- Dirección visual: estilo Apple (fondo casi negro, acento sutil, tipografía del sistema con contraste fuerte, tarjetas con bordes de luz, heroes a pantalla completa con degradado).
- Localización ES + EN mediante String Catalogs incluida en el plan.
- Orden de ejecución = orden de los bloques (por impacto).

---

## Bloque 0 — Correcciones habilitadoras

Rápidas, van primero para no contaminar el pulido.

| Entregable | Detalle | Fichero(s) |
|---|---|---|
| Fix inyección `DiscoveryModel` | `IntegrationsSection` usa `@EnvironmentObject` pero se inyecta con `.environment(...)` (Observation). Cambiar a `@Environment(DiscoveryModel.self)`. Riesgo real de crash en Perfil → Integraciones. | `Sources/ThisJellyFixFeature/IntegrationsSection.swift:16` |
| Validar token al restaurar sesión | `restoreSession` confía en token sin verificar (TODO línea 86-87). Validar contra `/Users/Me` y forzar login si 401. | `Sources/ThisJellyFixFeature/AuthModel.swift:78-91` |
| Limpiar VLCKit fantasma | `Package.resolved` sigue clavando `vlckit-spm` sin ningún consumidor. Regenerar/resolver. | `Package.resolved`, `thisjellyfix.xcodeproj` |
| Paginación de filas Home | Hoy límite 20 fijo sin `startIndex`/`limit` real. Preparar soporte de página para bloque 2. | `Sources/ThisJellyFixFeature/LibraryModel.swift:63-137` |

**Criterio "se nota premium":** nada crashea al navegar a Integraciones ni tras reiniciar con token caducado.

---

## Bloque 1 — Design System "La Marea"

Base de todo lo demás. Hoy no existe: colores inline (`.cyan` ×25, `.red`, `.mint`), espaciados en números sueltos (32/24/16), tipografía sistema sin escala.

### Tokens

| Token | Valor de partida (estilo Apple) |
|---|---|
| `Color.background` | Casi negro azulado — hoy `Color(red:0.05, green:0.08, blue:0.15)` en `ThisJellyFixRootView.swift:71` → oficializar |
| `Color.surface` / `surfaceElevated` | Hoy card `Color(red:0.12,0.14,0.22)` en `ImageView.swift:177` → oficializar + variante elevada |
| `Color.accent` | **Un** acento coherente (reemplaza los 25 `.cyan`, `.mint`, `.red` sueltos). Decidir: cian contenido (actual) o blanco puro como acento tipo Apple TV |
| `Color.borderGlow` | Borde sutil 1pt tipo luz en tarjetas enfocadas/hover |
| `Spacing` (`xs…xxl`) | Sustituye 32/24/16 hardcodeados en `HomeView`, `DetailView`, `ProfileView` |
| `Radius` | Radio de tarjeta, sheet, pill unificados (hoy dispersos) |
| `Typography` | Escala del sistema (largeTitle…caption2) con pesos semibold/bold consistentes; eliminar `.font(.system(size: 36))` / `size: 72` del player (`PlayerView.swift:860,869`) — ver bloque 7 Dynamic Type |
| `Shadow` | Sombra estándar de tarjeta + sombra de degradado sobre heroes |

### Componentes a consolidar

- **`MediaCardView`** — poster/16:9 + barra de progreso (`MediaCardView.swift`): aplicar tokens, borde de luz, estado de foco/hover tvOS-macOS.
- **`HeroCardView`** (nuevo) — para el billboard del bloque 2.
- **`ActionPill`** — ya existe (`DetailView.swift:826`), llevar a tokens.
- **`RowSection`** (nuevo) — cabecera con título + "Ver todo" + ScrollView de tarjetas con peek; reemplaza el `ScrollView(.horizontal)+LazyHStack` ad-hoc de `HomeView.swift:349`.
- **`SkeletonView`** (nuevo) — shimmer placeholder; reemplaza `ProgressView("Cargando…")`.
- **`MareaImageView`** — mantener lógica de caché; añadir blur-up suave y downsampling (ver bloque 6).

**Ficheros nuevos:** `Sources/ThisJellyFixFeature/DesignSystem/{Theme.swift, Typography.swift, Spacing.swift, Components/*.swift}`.
**Alcance de migración:** todas las vistas de `ThisJellyFixFeature` — sustituir literales por tokens.

**Criterio "se nota premium":** búsqueda de `\.cyan|\.mint|Color(red:` en Sources → 0 o solo en DesignSystem. Look coherente entre todas las pantallas.

---

## Bloque 2 — Home estilo streaming

Hoy: 5 filas hardcodeadas × 20 ítems, sin paginación, sin hero, sin "Ver todo", carga = `ProgressView`.

| Entregable | Detalle |
|---|---|
| **Hero billboard "Continuar viendo"** | Primer elemento del Home: backdrop 16:9 a ancho completo con degradado inferior, título grande, barra de progreso fina, CTA "Reanudar" (play pill). Datos del endpoint `/Items/Resume` ya consumido (`LibraryModel.refreshResume`). |
| **Filas con peek/snap** | `RowSection` con `scrollTargetBehavior(.viewAligned)` + `scrollTargetLayout` (iOS 17+/tvOS): la siguiente tarjeta asoma un margen. Aplicar en iOS, iPadOS, tvOS. |
| **"Ver todo" → pantalla de biblioteca** | Hoy no existe navegación de biblioteca (solo dos folder IDs para las filas). Grid paginado (`LazyVGrid`, carga al final de la lista), cabecera con título. Usa `fetchViews`/`/Users/{id}/Items` ya existentes con parámetros de página. |
| **Secciones dinámicas** | Sustituir las 5 filas fijas por lo que el dashboard real devuelve (respetando orden del servidor), manteniendo fallback a las actuales. |
| **Skeleton shimmer** | `SkeletonView` en filas mientras carga; desaparecer con la animación stagger existente (`HomeView.swift:382-388`). |
| **Pull-to-refresh** | Ya parcial; unificar con `refreshResume` cooldown. |

**Ficheros:** `HomeView.swift`, `LibraryModel.swift`, `DesignSystem/Components/RowSection.swift`, nuevo `LibraryGridView.swift`.

**Criterio "se nota premium":** abrir la app = pantalla de arranque tipo Apple TV (hero + filas con peek), cero `ProgressView` de texto.

---

## Bloque 3 — Detalle con profundidad

Hoy: hero estático, sin cast, sin "más como esto", sin tráileres; `UIScreen.main.bounds.height` para sizing (API deprecado, `DetailView.swift:806-812`).

| Entregable | Detalle |
|---|---|
| **Cast y equipo** | Sección "Reparto" horizontal con retratos (endpoint `/Items/{id}/Credits` o personas incluidas en detalle). Director guionista destacado. |
| **"Más como esto"** | Endpoint `/Items/{id}/Similar` (no consumido hoy). Fila `RowSection` reutilizando tarjetas. |
| **Tráiler / previews** | Detectar trailers en `MediaSources`/`People` (YouTube keys o tráiler del servidor) → botón "Tráiler" junto a "Reproducir". |
| **Transición hero→detalle** | `matchedGeometryEffect` del backdrop de la tarjeta al hero del detalle (iOS/tvOS/macOS). |
| **Parallax sutil** | Scroll del backdrop con desplazamiento reducido + degradado; sustituir `UIScreen.main.bounds` por `GeometryReader`/`containerRelativeFrame`. |
| **Capítulos** | Lista de capítulos (datos ya existentes vía `JellyfinSegmentClient` fallback) con salto directo. |
| **Acciones refinadas** | `ActionBarPill` con tokens: Reproducir (relleno), Tráiler, Favorito (con animación de estado), Marcar visto. |

**Ficheros:** `DetailView.swift` (hoy grande → considerar extraer secciones a `DetailView/Sections/*.swift`), `JellyfinItemDetailClient.swift` (añadir similar/credits/trailers).

**Criterio "se nota premium":** transición fluida tarjeta→detalle, la página responde preguntas "¿quién actúa?, ¿qué me recuerda?, ¿hay tráiler?".

---

## Bloque 4 — Player premium

El player es la zona más madura; aquí se sube de "muy bueno" a "premium".

| Entregable | Detalle |
|---|---|
| **Selector de calidad real** | `showQualityPicker` declarado sin usar (`PlayerViewModel.swift:61`). UI de hoja con opciones Auto/1080p/720p/480p → construir URL con `MaxStreamingBitrate` (escalera de `AVPlayerCapability.chooseURL` ya existe). |
| **Mini-player persistente** | Al cerrar el fullscreen hoy se pierde el acceso (solo Handoff/PiP restore). Barra mini-player al pie (sobre el tab bar) con tap → reabrir, swipe → descartar. Reutilizar instancia `AVPlayer` compartida (`AVPlaybackEngine` singleton por sesión). |
| **Tarjeta "Siguiente episodio" anticipada** | Panel con miniatura + cuenta atrás aparece ~30 s antes del fin (datos de fin de crédits ya detectados por `SegmentDetector`), no solo el overlay al final (`PlayerView.swift:1048-1102`). |
| **Gestos de seek** | Doble-tap izquierda/derecha ±10 s (hoy solo alterna fit/fill). Mantener swipe horizontal ±15 s actual. |
| **Brillo / volumen vertical** | Swipe vertical izquierda = brillo, derecha = volumen (`UIScreen.brightness` / `AVAudioSession` volume), estándar de apps de vídeo. tvOS: excluido (foco). |
| **Scrub con thumbnails** | Frames de previsualización al arrastrar la seek bar: usar imágenes `?Tag=` de Jellyfin (`/Videos/{id}/thumb` por timestamp) o capítulos como marcadores mínimos. |
| **Estilo de subtitles configurable** | Hoy overlay fijo `.title3.semibold` (`PlayerView.swift:231-245`). Ajustes: tamaño (Dynamic Type), fondo/opacidad, posición vertical. Preferencia persistida en UserDefaults. |
| **Buffering informativo** | Sustituir spinner por porcentaje/tiempo estimado cuando haya info de `loadedTimeRanges`. |

**Ficheros:** `PlayerViewModel.swift` (1081 líneas — extraer selectores a ficheros propios), `PlayerView.swift`, `AVPlaybackEngine.swift` (API de bitrate), nuevo `MiniPlayerView.swift`, `DesignSystem`.

**Criterio "se nota premium":** controles responden con haptics (bloque 6), calidad ajustable, y la sesión de audio sobrevive a cerrar el reproductor con UI para recuperarla.

---

## Bloque 5 — Navegación nativa por plataforma

### tvOS (hoy: compila, no está diseñado — 0 llamadas a focus engine)
- **Tabs propias:** hoy entra directo a `HomeView` (`ThisJellyFixRootView.swift:86-97`). Añadir `TabView` tvOS: Inicio / Buscar / Perfil (mismos tabs que iOS, iconos TV-friendly).
- **Focus engine:** `.focusable`, `prefersDefaultFocus`, `focusSection` por fila; tarjeta enfocada = escala + borde de luz (`borderGlow`) + título visible. Patrón Apple TV.
- **Top Shelf real:** sustituir imagen estática por contenido dinámico ("Continuar viendo" + últimos agregados) con `TVTopShelfContentProvider` (secretos/API key vía `Lockbox`/grupo compartido ya configurado en entitlements).
- **Layouts tvOS:** `#if os(tvOS)` en filas (más aire, tamaños mayores), `onExitCommand` ya existe en player — mantener.

### macOS (hoy: `NavigationSplitView` básico)
- **Sidebar enriquecida:** bibliotecas del servidor (via `fetchViews`) como destinos, no solo 3 secciones.
- **Toolbar:** buscar global, botón de conexión/estado del servidor, spacer flexible.
- **Atajos de teclado:** `⌘F` buscar, `←/→` skip en player, `espacio` play/pausa (`onKeyPress`/`KeyboardShortcut`).
- **Hover en tarjetas:** elevación + borde de luz (equivalente al foco tvOS).

### iOS / iPadOS
- **iPad:** `NavigationSplitView` o columnas cuando el ancho lo permita; soporte multitasking (Stage Manager) — verificar sin layout roto; puntero con foco visual en tarjetas.
- **Tab bar:** mantener `tabBarMinimizeBehavior` (iOS 26); dar espacio al mini-player del bloque 4.
- **Gestos de navegación:** swipe-back ya nativo; asegurar que no choque con gestos del player.

### visionOS (hoy: 9 líneas de `@main`)
- Layout base funcional con fondo compatible (`ornament`/volumen simple) para que no quede como app iOS pegada; nada ambicioso en esta fase.

**Ficheros:** `ThisJellyFixRootView.swift`, `HomeView.swift`, `Apps/tvOS/*` (Top Shelf), `Apps/macOS/*`.

**Criterio "se nota premium":** en Apple TV se navega todo con el mando con foco claro; en Mac se usa sin ratón innecesario (teclado); en iPad se ve como app diseñada, no redimensionada.

---

## Bloque 6 — Microinteracciones

| Entregable | Detalle |
|---|---|
| **Haptics / feedback sensorial** | 0 en toda la app. `sensoryFeedback(.impact, trigger:)` al: cambiar de tab, enfocar tarjeta (tvOS), toggle favorito, play/pausa, fin de skip countdown, seguir patrón del sistema (`.selection` para cambios de pista). |
| **Transiciones coherentes** | `matchedGeometryEffect` tarjeta→detalle (bloque 3); push/navigation con `.transition` uniforme; nada de animaciones ad-hoc distintas por vista. |
| **Skeleton shimmer** | Del bloque 1, con animación sutil respetando Reduce Motion. |
| **Estados vacíos amables** | Biblioteca vacía, búsqueda sin resultados, servidor caído — arte simple + copy + acción (hoy texto plano). |
| **Carga de imágenes** | Blur-up: placeholder de color → imagen difuminada → nítida (hoy caja con la primera letra, `ImageView.swift:175-183`). Downscaling al decode (hoy imagen a tamaño completo en memoria). |
| **Animaciones del player** | Controles con spring; auto-hide con la easeInOut actual pero más rápido; barras con snap a marcas/capítulos. |
| **Reduce Motion** | Respeta `accessibilityReduceMotion` en shimmer/stagger/parallax. |

**Ficheros:** `MediaCardView.swift`, `ImageView.swift`, `HomeView.swift`, `PlayerView.swift`, vistas puntuales.

**Criterio "se nota premium":** cada acción táctil/focal tiene respuesta; las imágenes cargan elegantes; nada aparece de golpe sin transición.

---

## Bloque 7 — Localización (ES + EN) y Accesibilidad

### Localización
- Migrar **todo** el copy a **String Catalogs** (`Localizable.xcstrings`) con español (idioma base, ya escrito) e inglés traducido. Objetivo: 0 literales de UI en vistas.
- Incluir: tabs, botones, errores de red, estados vacíos, ajustes, textos del player, avisos de `DownloadCoordinator` (Radarr/Sonarr).
- El nombre del servidor/usuario se localiza con `String(localized:)` donde aplique.
- Verificación: grep de strings en español dentro de vistas → 0.

### Accesibilidad
- **Dynamic Type:** eliminar tamaños fijos (`size: 36/72` en `PlayerView.swift:860,869`; revisar `largeTitle.bold()` fijos). Usar estilos de fuente escalables + `@ScaledMetric` para iconos/marcos donde haga falta.
- **VoiceOver:** `accessibilityLabel/Element` en tarjetas (título + año + progreso), acciones del player, orden en filas; agrupar tarjeta en un único elemento.
- **Reduce Motion:** ver bloque 6.
- **Contraste:** asegurar AA con fondo casi negro (los grises actuales revisarlos).
- **Focus tvOS:** ya en bloque 5; aquí se verifica teclado en iPad/macOS.

**Ficheros:** `Sources/ThisJellyFixFeature/**` (migración), `Apps/*/Info.plist` (idiomas), posibles tests de catálogo.

**Criterio "se nota premium":** la app se puede usar con VoiceOver, texto a tamaño grande sin romperse, y en inglés sin cambiar código.

---

## Bloque 8 — Roadmap posterior (mención, fuera del alcance de este plan)

Anotado para planificación futura, **no se ejecuta** en este plan:

- **Biblioteca completa:** filtros (género/año/estudio), orden, colecciones/boxsets, paginación avanzada.
- **Perfiles de usuario** con selector y PIN (Jellyfin lo soporta; hoy usuario único).
- **Siguiente episodio real:** usar endpoint `/Shows/NextUp` (hoy solo siguiente en temporada actual).
- **Notificaciones:** nuevos episodios, descargas Radarr/Sonarr terminadas (`UNUserNotificationCenter`).
- **Offline / descargas de vídeo** (hoy "Descargas" = órdenes Radarr/Sonarr).
- **Live TV, música, fotos** — extensiones de catálogo.
- **Widgets / Live Activity / Dynamic Island.**
- **`ResumePlaybackIntent` real** (hoy stub que no hace nada, `ResumePlaybackIntent.swift:15-17`).
- **CI:** no existe; añadir GitHub Actions con `swift test` + schemes compartidos.

---

## Orden de ejecución y dependencias

```
0 (fixes) → 1 (design system) → 2 (home) → 3 (detalle) → 4 (player)
                                    ↘ 5 (plataformas, requiere 1 y 2)
6 (microinteracciones) requiere 1 y 4
7 (localización/a11y) se hace al final sobre vistas estables (requiere 1-6)
```

- **Bloque 1 es bloqueante** para 2-6: no avanzar a vistas sin tokens.
- Los bloques 2-4 son independientes entre sí en ficheros, pueden paralelizarse.
- El bloque 5 aprovecha que 1 y 2 estén hechos para no hacer focus engine sobre componentes que van a cambiar.
- El bloque 7 va al final para no localizar textos que aún van a cambiar.

## Criterios globales de éxito

1. **Cero literales** de color/espaciado fuera del Design System.
2. **Cero `ProgressView` con texto** en rutas de carga principales.
3. **tvOS navegable al 100% con mando** (tabs + foco + top shelf).
4. **Haptics y VoiceOver** en las 10 interacciones más frecuentes.
5. **Catálogo ES/EN completo** sin IDs de idioma condicionales en código.
6. **`swift test` en verde** + añadir tests de lógica extraída de `PlayerViewModel`/`LibraryModel` al refactorizar.
