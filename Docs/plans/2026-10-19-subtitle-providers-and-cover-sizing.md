# Plan — Proveedores de subtítulos + tamaño de portadas de episodio

Fecha: 2026-10-19 · Rama: `main` · Decisiones confirmadas por el usuario.

## Problema 1 — Proveedores de subtítulos

### Hallazgo de investigación
- El OpenAPI estable de Jellyfin **no expone ningún endpoint para añadir proveedores de subtítulos al servidor**. Solo:
  - `GET /Items/{itemId}/RemoteSearch/Subtitles/{language}` (buscar)
  - `POST /Items/{itemId}/RemoteSearch/Subtitles/{subtitleId}` (descargar, el servidor lo guarda)
  - `GET /Providers/Subtitles/Subtitles/{subtitleId}` (fichero)
- Los proveedores del servidor son *plugins* de Jellyfin configurados en su panel web
  (`POST /Plugins/{pluginId}/Configuration` = solo credenciales de un plugin ya instalado, y exige admin).
- La app **sí** puede descargar un subtítulo por su cuenta y subirlo al servidor con
  `POST /Videos/{itemId}/Subtitles` (JSON `UploadSubtitleDto`: `Data`, `Language`, `Format`,
  `IsForced`, `IsHearingImpaired`) → el fichero entra como subtítulo externo y lo carga el
  pipeline de reproducción **existente**, sin tocarlo.

### Diseño (híbrido, confirmado)
Un registro único de proveedores con dos familias:
1. **Proveedor del servidor** (`jellyfinServer`): sin credenciales, usa el flujo actual
   (`JellyfinSubtitleClient.searchRemoteSubtitles` / `downloadRemoteSubtitle`). Intocable.
   Su interruptor de Ajustes **sí** se respeta en el reproductor.
2. **Proveedores en la app** (p. ej. `openSubtitles`): la app consulta la API externa con la
   API key del usuario (Keychain), descarga el `.srt` y lo **sube al servidor** con
   `POST /Videos/{itemId}/Subtitles`; después reutiliza la lógica existente de refresco + selección.

### Contrato de OpenSubtitles.com (verificado contra su cliente de referencia oficial
`opensubtitles/mcp.opensubtitles.com`, no de memoria)
- `GET /api/v1/subtitles` con los parámetros **ordenados alfabéticamente** y en minúsculas
  (el gateway responde 301 si no lo están): `query`, `imdb_id`, `tmdb_id`, `parent_imdb_id`,
  `parent_tmdb_id`, **`season_number`**, **`episode_number`**, `languages`.
  Los ids van canónicos: sin prefijo `tt` y sin ceros a la izquierda.
- La respuesta anida todo bajo **`attributes`** (`language`, `release`, `download_count`,
  `ratings`, `files[].file_id/file_name`, `hearing_impaired`, `ai_translated`…). La forma plana
  se acepta como respaldo.
- La descarga es **`POST /api/v1/download?file_id=N`** (el `file_id` del resultado), no
  `GET /api/v1/subtitles/{id}/download`: un subtítulo puede empaquetar varios ficheros.
- El `User-Agent` es **obligatorio** (sin él el gateway responde `kong-user-agent-block`).


### Ficheros
- `Sources/ThisJellyFixCore/SubtitleProvider.swift` — catálogo, descriptor, config, errores.
- `Sources/ThisJellyFixCore/SubtitleProviderStore.swift` — persistencia (UserDefaults + Keychain).
- `Sources/ThisJellyFixCore/ExternalSubtitleResult.swift` — resultado unificado servidor/app.
- `Sources/ThisJellyFixNetworking/OpenSubtitlesClient.swift` — cliente real (search + download).
- `Sources/ThisJellyFixNetworking/JellyfinSubtitleClient.swift` — + `uploadExternalSubtitle`.
- `Sources/ThisJellyFixFeature/SubtitleProvidersSection.swift` — sección de Ajustes.
- `Sources/ThisJellyFixFeature/SubtitleProviderEditorSheet.swift` — alta/edición.
- `Sources/ThisJellyFixFeature/SettingsView.swift` — monta la sección.
- `Sources/ThisJellyFixFeature/PlayerViewModel.swift` / `PlayerView.swift` — búsqueda multifuente.

## Problema 2 — Portadas de episodio demasiado grandes

### Causas concretas
1. `MediaCardView` fuerza un ancho **fijo** (240 pt iOS / 320 pt macOS) para episodios sin mirar
   el contenedor. En las rejillas adaptativas (Buscar: `GridItem(.adaptive(minimum: 120))`,
   ~161 pt de columna en iPhone, ~131 pt en macOS) la tarjeta desborda la celda un 33-150 %
   y se solapa con la columna vecina. En las filas horizontales el ancho sí es el correcto →
   de ahí el comportamiento "inconsistente".
2. La URL del episodio es siempre `Images/Primary` (vertical 2:3) pero la tarjeta es 16:9 con
   `.aspectRatio(contentMode: .fill)` → ampliación ~2,7x + recorte brutal.
3. `MareaImageView` en modo flexible (0/0) hace `frame(maxWidth:.infinity, maxHeight:.infinity)`
   **sin `clipShape`** y sin tamaño intrínseco acotado: depende del caller, y el placeholder y el
   `ProgressView` se encuadran dos veces (asimetría entre estados).

### Solución (adaptativa + arte correcto, confirmada)
- `MediaCardLayout` (Core, geometría pura testeable): `.poster` (2:3) y `.landscape` (16:9).
- `MediaCardView`: ancho **ligado al contenedor** (`.flexible` en rejillas → nunca desborda la
  columna) o fijo (`.fixed` en filas horizontales, que ya hacen scroll).
- `JellyfinArtwork` (Core): un único constructor de URL que elige la imagen que corresponde a la
  forma de la tarjeta (Thumb → Backdrop → Primary en 16:9; Primary en 2:3) y pide el recorte
  exacto al servidor (`fillWidth`/`fillHeight`) → sin re-ampliación en cliente.
- `MareaImageView`: recorte siempre aplicado, un solo encuadre, modo `aspectRatio` para cajas adaptativas.

## Verificación

### Comprobaciones ejecutadas
| Comprobación | Resultado |
|---|---|
| `swift build` (SPM, macOS host) | ✅ Build complete |
| `swift test` (SPM) | ✅ 264 tests, 0 fallos (5 suites) |
| `xcodebuild thisjellyfix-iOS` (simulador) | ✅ BUILD SUCCEEDED |
| `xcodebuild thisjellyfix-macOS` | ✅ BUILD SUCCEEDED |
| `xcodebuild thisjellyfix-tvOS` | ✅ BUILD SUCCEEDED |
| `xcodebuild thisjellyfix-visionOS` | ❌ FALLA **preexistente** (verificada también en `HEAD` limpio): `AVPlayer.isExternalPlaybackActive` no existe en visionOS (`PlayerViewModel.swift:738/760`). No está relacionada con estos cambios. |
| `swift test` (repeticiones) | ⚠️ 1 de cada ~4 ejecuciones el proceso de `ThisJellyFixFeatureTests` muere con signal 11. **Preexistente**: reproducido también en `14e5373` (1 de 8 ejecuciones). Es la suite que instancia `AVPlayer` contra `127.0.0.1:1`. |

### Mediciones empíricas del layout (SwiftUI real, `NSHostingView`)
Reproduciendo la rejilla de Búsqueda (`LazyVGrid(.adaptive(minimum: 120))` en 337 pt):

| Escenario | Antes | Después |
|---|---|---|
| Ancho de la celda | 157,5 pt | 157,5 pt |
| Ancho de la portada de episodio | **240 pt** (desbordaba 82,5 pt = **52 %**) | **157,5 pt** (cabe) |
| Caja adaptativa 16:9 con póster 2:3 | — | 161 × 91 ✓ |
| Caja fija 240 × 135 con póster 2:3 | 240 × 135 | 240 × 135 ✓ (sin cambios) |
| Modo flexible (hero) en 300 × 520 | 300 × 520 | 300 × 520 ✓ |

### Tests añadidos
- `MediaCardLayoutTests` — geometría, ratio por forma, el artwork que se pide y el `fillWidth`/`fillHeight` exacto.
- `SubtitleProviderStoreTests` — persistencia, duplicados, borrado, la clave vive en el Keychain (y **no** en `UserDefaults`), validación.
- `OpenSubtitlesClientTests` — ruta, cabeceras obligatorias, decodificación (id numérico y de texto), mapeo de errores, descarga con gunzip real.
- `JellyfinSubtitleUploadTests` — el cuerpo JSON exacto de `UploadSubtitleDto` (los cinco campos, sin extras).

