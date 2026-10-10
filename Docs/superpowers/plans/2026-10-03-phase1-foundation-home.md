# Fase 1 — Fundación premium (Fixes + Design System + Home) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplicar la base premium acordada en el spec: fixes habilitadores, design system "La Marea" (tokens + componentes) y la nueva Home estilo streaming (chips, hero carrusel, filas con peek/"Ver todo", fondo negro puro, tab bar flotante).

**Architecture:** SwiftPM multi-target (Core/Networking/Discovery/Playback/Feature), SwiftUI + `@Observable`, cero dependencias de terceros. Esta fase añade `DesignSystem/` dentro de `ThisJellyFixFeature`, un target de tests nuevo `ThisJellyFixFeatureTests`, y refactoriza `HomeView`/`LibraryModel` sin tocar el player. Cada tarea es un commit atómico en verde (`swift build` + `swift test`).

**Tech Stack:** Swift 5.10, SwiftUI (iOS 17+/macOS 14+/tvOS 17+/visionOS 1+), URLSession hand-rolled, swift-tools 5.10.

**Spec:** `Docs/superpowers/specs/2026-10-03-premium-experience-plan.md` (bloques 0, 1 y 2; sección "Referencia visual de la página de inicio"). Los bloques 3-7 se planifican en fases posteriores con sus propios planes.

## Global Constraints

- **Cero dependencias SPM de terceros** (`Package.swift` `dependencies: []` se mantiene).
- **Deployment targets:** iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0 — no usar APIs superiores sin `#available`/`if #available`.
- **Copy de UI en español** (la migración a String Catalogs es bloque 7, fase posterior — no hacer aquí).
- **Verificación por tarea:** `swift build && swift test` desde la raíz del repo. Solo `swift test` ejecuta la suite (no hay test targets de Xcode).
- **Convención del repo:** comentarios en inglés explicando el *por qué*; `TJFLog(...)` para logging; modelos `@MainActor @Observable final class`.
- **No romper Handoff/PiP:** `LibraryModel.pendingNavigationItem`, `pendingNavigationPosition` y `hasLoaded` conservan comportamiento (ver comentarios en `HomeView.swift` y `LibraryModel.swift`).
- **Nombres de fila:** los títulos de fila del modelo se quedan en español ("Estás viendo", …) — `ContentRow.id == title`; no renombrarlos en esta fase (rompería `rowOrder` y `refreshResume`).
- **Accent unificado:** `MareaTheme.Colors.accent` = rojo Netflix `Color(red: 0.90, green: 0.06, blue: 0.13)` para tint/progress/tab; CTAs primarios en blanco (referencia: capturas Netflix).

## Review Focus

- **Handoff tras refactor de Home:** push programático desde `pendingNavigationItem` debe seguir funcionando en iOS y macOS (test: no romper el flujo; verificar builds + revisión del código de `onChange` handlers al final).
- **`refreshResume` cooldown/force:** el rebuild de Home no debe duplicar ni perder el refresh post-playback (las anotaciones de `LibraryModel` documentan regresiones pasadas — leer antes de tocar).
- **Paginación vs. `load()` paralelo:** `startIndex` en `fetchItems` cambia la firma del protocolo — todos los call sites y stubs de test deben actualizarse en la misma tarea.
- **tvOS/visionOS:** `HomeView` compila en las 4 plataformas; los componentes nuevos deben usar `#if os(...)` donde la API no exista (p.ej. `Tab` de iOS 18, materiales de barra).
- **`IntegrationsSection` tras el fix de inyección:** verificar en runtime que Perfil → Integraciones muestra datos (era crash latente).

---

### Task 1: Fix `IntegrationsSection` — inyección de `DiscoveryModel`

**Files:**
- Modify: `Sources/ThisJellyFixFeature/IntegrationsSection.swift:16`
- Test: sin test (vista); verificación = build + revisión

**Interfaces:**
- Consumes: `DiscoveryModel` (`@Observable`, inyectado con `.environment(discoveryModel)` en `ThisJellyFixRootView.swift:84,97` y `DownloadsButton.swift:38`).
- Produces: sin cambio de interfaz pública.

- [ ] **Step 1: Cambiar la anotación**

`@EnvironmentObject private var discovery: DiscoveryModel` → `@Environment(DiscoveryModel.self) private var discovery: DiscoveryModel`. Ajustar el uso si el compilador lo pide (misma API de lectura por Observation).

- [ ] **Step 2: Build en verde**

Run: `swift build`
Expected: BUILD SUCCEEDS (el `@EnvironmentObject` con inyección `.environment` era crash latente en runtime, no de compilación).

- [ ] **Step 3: Commit**

```bash
git add Sources/ThisJellyFixFeature/IntegrationsSection.swift
git commit -m "fix(profile): inject DiscoveryModel via Observation environment"
```

---

### Task 2: Validación de token en restore — `validateToken` en Networking

**Files:**
- Modify: `Sources/ThisJellyFixNetworking/JellyfinAuthClient.swift` (protocolo `JellyfinAuthenticating` + `JellyfinAuthClient`)
- Test: `Tests/ThisJellyFixNetworkingTests/JellyfinAuthClientTests.swift` (reutiliza el stub `URLProtocol` ya existente del fichero)

**Interfaces:**
- Consumes: `JellyfinNetworkSession`, `AuthError`, `JellyfinUser` (Core).
- Produces: `func validateToken(userId: String, serverURL: URL, token: String) async throws -> JellyfinUser` en `JellyfinAuthenticating` — la usa `AuthModel` en Task 3.

- [ ] **Step 1: Test fallido — token válido devuelve usuario**

Añade a `JellyfinAuthClientTests` un test que registra un stub con `GET /Users/{userId}` → 200 + JSON `{"Id":"u1","Name":"Joel"}` y assert `try await client.validateToken(userId: "u1", serverURL: url, token: "t") == JellyfinUser(id: "u1", name: "Joel")`. Copia el patrón de registro del stub existente del fichero.

- [ ] **Step 2: Test fallido — 401 lanza `AuthError.invalidCredentials`**

Mismo stub con respuesta 401; `XCTAssertThrowsError` con assert `as? AuthError == .invalidCredentials`.

- [ ] **Step 3: Ejecutar y ver fallar**

Run: `swift test --filter JellyfinAuthClientTests`
Expected: FAIL — `validateToken` no existe / no cumple el protocolo.

- [ ] **Step 4: Implementar `validateToken`**

Añade al protocolo y a la struct: `GET` a `Users/{userId}` con header `Authorization` igual al de `authenticate` (reutiliza `authorizationHeader(deviceId:)` — necesita el deviceId; añade `deviceId` al método o pasa uno fijo del caller; decisión: firma `validateToken(userId:serverURL:token:deviceId:)` para reutilizar el header tal cual). Manejo de status: 200 → decodifica `JellyfinUser`; 401 → `.invalidCredentials`; resto → `.serverError(code)`; error de red → `.networkError`.

- [ ] **Step 5: Ejecutar y ver pasar**

Run: `swift test --filter JellyfinAuthClientTests`
Expected: PASS (todos los tests del fichero).

- [ ] **Step 6: Build completo + commit**

Run: `swift build && swift test`
Expected: verde. (Cuidado: añadir el método al protocolo rompe conformadores dummy en otros tests — actualizarlos si aparecen.)

```bash
git add Sources/ThisJellyFixNetworking/JellyfinAuthClient.swift Tests/ThisJellyFixNetworkingTests/
git commit -m "feat(auth): add validateToken via GET /Users/{id}"
```

---

### Task 3: `AuthModel.restoreSession` valida contra el servidor

**Files:**
- Create: `Tests/ThisJellyFixFeatureTests/AuthModelTests.swift`
- Create: `Tests/ThisJellyFixFeatureTests/TestSupport.swift` (mocks: `MockKeychain`, `MockAuthClient`)
- Modify: `Package.swift:26-35` (añadir test target)
- Modify: `Sources/ThisJellyFixFeature/AuthModel.swift:78-91`

**Interfaces:**
- Consumes: `KeychainStoring` (Core), `JellyfinAuthenticating.validateToken` (Task 2), `KeychainKey`.
- Produces: `restoreSession(serverURL:) async -> Bool` conserva firma; comportamiento nuevo: `false` + keychain limpiado si el token es inválido (401).

- [ ] **Step 1: Añadir test target a `Package.swift`**

`.testTarget(name: "ThisJellyFixFeatureTests", dependencies: ["ThisJellyFixFeature", "ThisJellyFixCore", "ThisJellyFixNetworking"])`.

- [ ] **Step 2: Escribir soporte de test**

`TestSupport.swift`: `MockKeychain: KeychainStoring` con diccionario en memoria (ver `Tests/ThisJellyFixCoreTests/KeychainStoreTests.swift` para la firma exacta de `KeychainStoring`); `MockAuthClient: JellyfinAuthenticating` con `validateTokenResult: Result<JellyfinUser, Error>` y `authenticate` fatal.

- [ ] **Step 3: Test fallido — token inválido (401) → `false` y keychain limpio**

Prepara `MockKeychain` con token/userId/userName; `MockAuthClient.validateTokenResult = .failure(AuthError.invalidCredentials)`. `restoreSession` → `false`; keychain ya no contiene `accessToken`.

- [ ] **Step 4: Test fallido — token válido → `true` y `currentUser` poblado**

`validateTokenResult = .success(JellyfinUser(id:"u1", name:"Joel"))` → `restoreSession` → `true`, `authModel.currentUser?.name == "Joel"`, `isAuthenticated == true`.

- [ ] **Step 5: Ejecutar y ver fallar**

Run: `swift test --filter AuthModelTests`
Expected: FAIL — hoy `restoreSession` confía en el token sin validar.

- [ ] **Step 6: Implementar validación en `restoreSession`**

Tras leer el keychain: `let user = try await authClient.validateToken(userId:userId, serverURL:serverURL, token:token, deviceId:deviceId)`. Éxito → `currentUser = user; isAuthenticated = true; return true`. `AuthError.invalidCredentials` (o cualquier error) → `logout()` (limpia keychain y estado) y `return false`.

- [ ] **Step 7: Ejecutar y ver pasar**

Run: `swift test --filter AuthModelTests`
Expected: PASS.

- [ ] **Step 8: Suite completa + commit**

Run: `swift build && swift test`
Expected: verde.

```bash
git add Package.swift Sources/ThisJellyFixFeature/AuthModel.swift Tests/ThisJellyFixFeatureTests/
git commit -m "feat(auth): validate restored session token via /Users/{id}"
```

---

### Task 4: Limpieza VLCKit fantasma

**Files:**
- Modify: `thisjellyfix.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

**Interfaces:** sin cambios de código.

- [ ] **Step 1: Regenerar resolución de paquetes**

Run: `xcodebuild -project thisjellyfix.xcodeproj -resolvePackageDependencies`
Expected: `Package.resolved` deja de pinar `virtualox/vlckit-spm` (ningún target lo referencia).

- [ ] **Step 2: Verificar build Xcode de una plataforma**

Run: `xcodebuild -project thisjellyfix.xcodeproj -scheme thisjellyfix-macOS -derivedDataPath /tmp/tjf-dd build -quiet`
Expected: BUILD SUCCEEDS.

- [ ] **Step 3: Commit**

```bash
git add thisjellyfix.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "chore: drop stale VLCKit pin from Package.resolved"
```

---

### Task 5: `startIndex` en `fetchItems` (paginación en Networking)

**Files:**
- Modify: `Sources/ThisJellyFixNetworking/JellyfinLibraryClient.swift:36-95`
- Test: `Tests/ThisJellyFixNetworkingTests/JellyfinLibraryClientTests.swift`
- Modify (call sites/stubs): `Sources/ThisJellyFixFeature/LibraryModel.swift` (5 llamadas), cualquier stub `JellyfinLibraryProviding` en tests (grep en `Tests/`).

**Interfaces:**
- Consumes: `fetchItems` actual.
- Produces: `func fetchItems(userId:serverURL:token:parentId:includeTypes:limit:orderBy:filters:startIndex: Int?) async throws -> [JellyfinMediaItem]` — `nil` = sin paginar (comportamiento actual). Lo usan Task 10/11.

- [ ] **Step 1: Test fallido — `startIndex` aparece en la query**

Extiende `testFetchItems` o añade `testFetchItemsPagination`: llama con `startIndex: 40` y assert en la URL capturada por el stub que contiene `StartIndex=40`.

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `swift test --filter JellyfinLibraryClientTests`
Expected: FAIL — el parámetro no compila aún.

- [ ] **Step 3: Implementar**

Añade `startIndex: Int? = nil` a protocolo y método; en `fetchItems`, si `startIndex != nil` añadir `URLQueryItem(name: "StartIndex", value: String(...))`. Actualiza todos los call sites (los de `LibraryModel` no lo pasan → default `nil`) y conformadores stub.

- [ ] **Step 4: Ejecutar y ver pasar**

Run: `swift test --filter JellyfinLibraryClientTests && swift build`
Expected: PASS + build verde.

- [ ] **Step 5: Suite completa + commit**

Run: `swift test`
Expected: verde.

```bash
git add Sources/ThisJellyFixNetworking/JellyfinLibraryClient.swift Sources/ThisJellyFixFeature/LibraryModel.swift Tests/
git commit -m "feat(networking): support StartIndex pagination in fetchItems"
```

---

### Task 6: Test target Feature + `MareaTheme` (tokens)

**Files:**
- Create: `Sources/ThisJellyFixFeature/DesignSystem/MareaTheme.swift`
- Test: `Tests/ThisJellyFixFeatureTests/MareaThemeTests.swift`

**Interfaces:**
- Consumes: SwiftUI.
- Produces (todo `public`-equivalente interno al módulo; el target Feature no expone API pública — `internal` basta):
  - `enum MareaTheme` con:
    - `Colors`: `background` (`Color.black`), `surface` (`Color(red:0.11,green:0.11,blue:0.12)`), `surfaceElevated` (`Color(red:0.16,green:0.16,blue:0.18)`), `glass` (`Color.white.opacity(0.08)`), `badgeRed` (`Color(red:0.90,green:0.06,blue:0.13)`), `accent` (= `badgeRed`), `borderGlow` (`Color.white.opacity(0.18)`), `heroFallback` (`Color(red:0.08,green:0.1,blue:0.18)`).
    - `Spacing`: `xs=4, sm=8, md=16, lg=24, xl=32` (`CGFloat`).
    - `Radius`: `card=12`, `hero=24`, `small=8` (`CGFloat`).
- Consumido por Tasks 7-12.

- [ ] **Step 1: Test fallido — colores y espaciados**

`MareaThemeTests`: asserts de igualdad — `MareaTheme.Colors.background == Color.black`, `MareaTheme.Spacing.xl == 32`, `MareaTheme.Radius.hero == 24`, `MareaTheme.Colors.accent == MareaTheme.Colors.badgeRed`.

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `swift test --filter MareaThemeTests`
Expected: FAIL — tipos no existen.

- [ ] **Step 3: Implementar `MareaTheme.swift`**

Enum anidado con los valores de arriba. Comentario de cabecera: "Design tokens for La Marea. Single source of truth — no raw colors/spacing outside DesignSystem."

- [ ] **Step 4: Ejecutar y ver pasar**

Run: `swift test --filter MareaThemeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ThisJellyFixFeature/DesignSystem/ Tests/ThisJellyFixFeatureTests/MareaThemeTests.swift
git commit -m "feat(design): add MareaTheme design tokens"
```

---

### Task 7: Lógica pura de badges de tarjeta

**Files:**
- Create: `Sources/ThisJellyFixFeature/DesignSystem/CardBadge.swift`
- Test: `Tests/ThisJellyFixFeatureTests/CardBadgeTests.swift`

**Interfaces:**
- Consumes: `JellyfinMediaItem` (Core).
- Produces:
  - `enum CardBadge: Equatable { case newSeason; case nextEpisode(day: String?) }`
  - `extension CardBadge { static func badge(for item: JellyfinMediaItem, resumeItems: Set<String>) -> CardBadge? }` — reglas: si `item.id` ∈ `resumeItems` → `.nextEpisode(day: nil)`; si `item.type == "Series"` y `item.userData?.played == false` y no está en resume → `.newSeason` (marcador simple de "sin terminar"; la variante "próximamente"/día se refina en fase de detalle); en otro caso `nil`.

- [ ] **Step 1: Test fallido**

Construye `JellyfinMediaItem` de prueba (el memberwise `init` es `public` — verificar parámetros; si el Codable no expone init, decodificar desde JSON de fixture como hacen otros tests de Core). Casos: item en resume → `.nextEpisode(day: nil)`; Series no jugada fuera de resume → `.newSeason`; Movie no jugada → `nil`; Series jugada → `nil`.

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `swift test --filter CardBadgeTests`
Expected: FAIL — tipo no existe.

- [ ] **Step 3: Implementar `CardBadge`**

Reglas de arriba, en un solo método estático puro (sin vistas).

- [ ] **Step 4: Ejecutar y ver pasar + commit**

Run: `swift test --filter CardBadgeTests && swift build` → verde.

```bash
git add Sources/ThisJellyFixFeature/DesignSystem/CardBadge.swift Tests/ThisJellyFixFeatureTests/CardBadgeTests.swift
git commit -m "feat(design): pure card badge logic"
```

---

### Task 8: Componentes base — `ChipView`, `BadgeView`, `SkeletonView`

**Files:**
- Create: `Sources/ThisJellyFixFeature/DesignSystem/ChipView.swift`
- Create: `Sources/ThisJellyFixFeature/DesignSystem/BadgeView.swift`
- Create: `Sources/ThisJellyFixFeature/DesignSystem/SkeletonView.swift`
- Test: sin tests de vista; verificación = build (los componentes se consumen en Tasks 9-12)

**Interfaces:**
- Consumes: `MareaTheme` (Task 6), `CardBadge` (Task 7).
- Produces:
  - `struct ChipView: View { let title: String; var isSelected: Bool = false }` — cápsula `MareaTheme.Spacing.xs/sm` padding, fondo `glass`, seleccionado: fondo `Color.white.opacity(0.9)` + texto negro, `Capsule()` shape, `MareaTheme.Spacing.sm` entre chips.
  - `struct BadgeView: View { let badge: CardBadge }` — `.newSeason`: texto "Nueva temporada", fondo `badgeRed`, blanco, bold caption, esquina inferior-izquierda; `.nextEpisode(let day)`: texto "Siguiente episodio" (+ `day` si no nil en línea de abajo), fondo blanco, texto negro.
  - `struct SkeletonView: View { let width: CGFloat; let height: CGFloat; var cornerRadius: CGFloat = MareaTheme.Radius.card }` — rectángulo `MareaTheme.Colors.surface` con shimmer sutil (`opacity` animada infinita; respetar `@Environment(\.accessibilityReduceMotion)` — sin animación si reduce motion).
- `RowSection` y `HeroCardView` van en Tasks 9 y 10.

- [ ] **Step 1: Implementar los tres componentes**

Con tokens de `MareaTheme`, sin colores/espaciados crudos.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: BUILD SUCCEEDS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ThisJellyFixFeature/DesignSystem/
git commit -m "feat(design): chip, badge and skeleton components"
```

---

### Task 9: `MediaCardView` con tokens + badge; `RowSection` con peek/"Ver todo"

**Files:**
- Modify: `Sources/ThisJellyFixFeature/MediaCardView.swift`
- Create: `Sources/ThisJellyFixFeature/DesignSystem/RowSection.swift`
- Modify: `Sources/ThisJellyFixFeature/HomeView.swift:372-426` (`ContentRowView` → usa `RowSection`)
- Test: sin tests de vista; verificación = build

**Interfaces:**
- Consumes: `MareaTheme`, `BadgeView`, `SkeletonView`; `MediaCardView` actual.
- Produces:
  - `MediaCardView` con añadidos: `var badge: CardBadge? = nil` (renderiza `BadgeView` overlay abajo-izquierda sobre la imagen), radios/colores por tokens (`cornerRadius: MareaTheme.Radius.card`, barra de progreso en `accent`), borde 1pt `borderGlow` cuando `isWide`.
  - `struct RowSection: View { let title: String; let items: [JellyfinMediaItem]; var wide: Bool = false; var badgeFor: ((JellyfinMediaItem) -> CardBadge?)? = nil; var imageURL: (JellyfinMediaItem) -> URL?; var onPlayDirect: ((JellyfinMediaItem) -> Void)? = nil; var onSeeAll: (() -> Void)? = nil }` — cabecera: título `title3.bold()` + `Ver todo ›` (botón, visible si `onSeeAll != nil`), horizontal ScrollView con `scrollTargetBehavior(.viewAligned)` + `scrollTargetLayout` (peek), tarjetas del tipo actual (NavigationLink vs play directo según tipo), stagger de aparición existente. tvOS/visionOS: sin "Ver todo" (sin `LibraryGridView` en esas plataformas por ahora — `onSeeAll` nil).

- [ ] **Step 1: Actualizar `MediaCardView`**

Añadir `badge`, migrar colores/radius a tokens (`.cyan` de la barra → `MareaTheme.Colors.accent`; color de placeholder `Color(red:0.12,...)` en `ImageView.swift:177` → `MareaTheme.Colors.surface`).

- [ ] **Step 2: Implementar `RowSection`**

Migrar la lógica de `ContentRowView` (card + NavigationLink/play-directo + stagger) y añadir cabecera con "Ver todo" + peek.

- [ ] **Step 3: Reemplazar `ContentRowView` en `HomeView`**

`ContentRowView` pasa a ser un wrapper delgado sobre `RowSection` (o se elimina y se llama `RowSection` directamente en el `ForEach`), manteniendo `isResumeRow` (wide) y el fallback de imagen del resume.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: BUILD SUCCEEDS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ThisJellyFixFeature/
git commit -m "feat(home): RowSection with peek, see-all and card badges"
```

---

### Task 10: `HeroCardView` + selección de héroes en `LibraryModel`

**Files:**
- Create: `Sources/ThisJellyFixFeature/DesignSystem/HeroCardView.swift`
- Modify: `Sources/ThisJellyFixFeature/LibraryModel.swift`
- Test: `Tests/ThisJellyFixFeatureTests/LibraryModelHeroTests.swift`

**Interfaces:**
- Consumes: `MareaTheme`, `JellyfinMediaItem`, `LibraryModel.rows`.
- Produces:
  - `LibraryModel`: `var heroItems: [JellyfinMediaItem]` — hasta 5: hasta 3 de "Estás viendo" (orden original) + relleno de "Últimos agregados" descartando duplicados; vacío si no hay filas. Lógica pura testeable sin red (construir `LibraryModel` con stub client y publicar filas).
  - `struct HeroCardView: View { let item: JellyfinMediaItem; let backdropURL: URL?; let posterURL: URL?; let onPlay: () -> Void }` — card grande `RoundedRectangle(cornerRadius: MareaTheme.Radius.hero)`, backdrop con `MareaImageView` (fallback a póster), degradado inferior (`LinearGradient` negro → transparente), badge pill "▶ SEGUIR VIENDO" arriba-izquierda (si `item.playedPercentage != nil`), panel glass inferior: póster pequeño + título (headline) + `item.overview` (2 líneas, subheadline secondary) + chips de metadatos (`item.communityRating` con estrella, `item.year`, `item.officialRating`) + barra de progreso fina (si hay `playedPercentage`) + botón blanco pill "▶ Reproducir" (`onPlay`). Tarjeta navega a detalle vía `NavigationLink(value: item)` — el botón play dispara `onPlay`.

- [ ] **Step 1: Test fallido — `heroItems`**

`LibraryModelHeroTests`: crea `LibraryModel` con stub `JellyfinLibraryProviding` (mock en memoria; ver firma del protocolo), publica 3 resume + 5 latest → `heroItems.count == 5`, primeros 3 = resume, sin ids duplicados; sin filas → `[]`.

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `swift test --filter LibraryModelHeroTests`
Expected: FAIL — `heroItems` no existe.

- [ ] **Step 3: Implementar `heroItems` en `LibraryModel`**

Computed property pura sobre `rows` (no fetch nuevo — datos ya cargados).

- [ ] **Step 4: Implementar `HeroCardView`**

Vista de arriba con tokens.

- [ ] **Step 5: Ejecutar y ver pasar + build**

Run: `swift test --filter LibraryModelHeroTests && swift build` → verde.

```bash
git add Sources/ThisJellyFixFeature/ Tests/ThisJellyFixFeatureTests/LibraryModelHeroTests.swift
git commit -m "feat(home): hero carousel model and HeroCardView"
```

---

### Task 11: `LibraryGridView` — "Ver todo" paginado

**Files:**
- Create: `Sources/ThisJellyFixFeature/LibraryGridView.swift`
- Modify: `Sources/ThisJellyFixFeature/LibraryModel.swift` (método de página)
- Test: `Tests/ThisJellyFixFeatureTests/LibraryModelPaginationTests.swift`
- Plataformas: `#if os(iOS) || os(macOS)` (como `SearchView`/`FavoritesView`)

**Interfaces:**
- Consumes: `fetchItems(startIndex:)` (Task 5), `MareaTheme`, `MediaCardView`.
- Produces:
  - `LibraryModel`: `func fetchPage(parentId: String?, includeTypes: String?, limit: Int = 30) async -> [JellyfinMediaItem]` — llama `fetchItems` con `startIndex: nil`; y estado de paginado encapsulado en la vista (no en el modelo): `LibraryGridView` guarda `items`, `startIndex`, `isLoadingPage`, `hasMore`; carga inicial + `onAppear` de la última celda → siguiente página; fin cuando la página devuelva `< limit`.
  - `struct LibraryGridView: View { let title: String; let parentId: String?; let includeTypes: String?; let serverURL: URL; let token: String; let userId: String }` — `NavigationStack` propio no (va empujada desde Home), `LazyVGrid` de columnas adapativas (portrait: 3, landscape/mac: 5-6), tarjetas `MediaCardView` con `NavigationLink(value:)`, skeleton en carga, cabecera con título.

- [ ] **Step 1: Test fallido — `fetchPage` pagina con `startIndex`**

`LibraryModelPaginationTests`: stub client que registra llamadas; `fetchPage(limit: 30)` → primera llamada sin `StartIndex`; segunda página simulada → assert de propagación de parámetros al stub (controlar qué devuelve el mock por `startIndex`).

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `swift test --filter LibraryModelPaginationTests`
Expected: FAIL.

- [ ] **Step 3: Implementar `fetchPage` en `LibraryModel`**

Wrapper fino sobre `libraryClient.fetchItems` con `startIndex` explícito.

- [ ] **Step 4: Implementar `LibraryGridView`**

Vista de arriba; registro de `navigationDestination(for: JellyfinMediaItem.self)` igual que Home (DetailView factory mínima — reutilizar los mismos parámetros; si el constructor de `DetailView` lo complica, pasar `handoffPosition: nil`).

- [ ] **Step 5: Test pasar + build**

Run: `swift test --filter LibraryModelPaginationTests && swift build` → verde.

- [ ] **Step 6: Commit**

```bash
git add Sources/ThisJellyFixFeature/ Tests/ThisJellyFixFeatureTests/LibraryModelPaginationTests.swift
git commit -m "feat(home): paginated LibraryGridView behind See All"
```

---

### Task 12: Nueva `HomeView` — header, chips, hero, filas

**Files:**
- Modify: `Sources/ThisJellyFixFeature/HomeView.swift` (`scrollContent`)
- Modify: `Sources/ThisJellyFixFeature/LibraryModel.swift` (chips/mapeo de vistas)
- Test: `Tests/ThisJellyFixFeatureTests/LibraryModelCategoryTests.swift`

**Interfaces:**
- Consumes: `RowSection` (9), `HeroCardView` + `heroItems` (10), `LibraryGridView` (11), `ChipView`/`SkeletonView` (8), `MareaTheme`.
- Produces:
  - `LibraryModel`: `var moviesParentId: String?`, `seriesParentId: String?` (exponer los ids ya obtenidos de `fetchViews` en `load()`, hoy locales) + `struct CategoryChip: Identifiable, Equatable { let id: String; let title: String; let parentId: String?; let includeTypes: String? }` y `var categoryChips: [CategoryChip]` — "Películas" (moviesParent), "Series" (seriesParent); solo aparecen si el id existe.
  - `HomeView.scrollContent` reordenado (referencia: sección "Referencia visual" del spec):
    1. Header: AppIcon + "Inicio" largeTitle + acciones a la derecha (DownloadsButton si aplica — se mantiene).
    2. Chips: `ScrollView(.horizontal)` de `ChipView`; tap → push `LibraryGridView` (navegación por valor: `NavigationPath` con un wrapper `Route: Hashable { case grid(CategoryChip) }` o `navigationDestination(for: CategoryChip.self)`).
    3. Hero carousel: `TabView` de estilo `.page` con `HeroCardView` por `libraryModel.heroItems`, dots del sistema; `onPlay` → mismo camino que `directItem` actual (fullScreenCover `DirectPlayer`) reanudando posición (`resumePositionSeconds`).
    4. Filas: `ForEach(rows)` → `RowSection` con `onSeeAll` (title "Películas"/"Series" → `LibraryGridView` con el parentId correspondiente) y `badgeFor` (resume → `.nextEpisode`, series de "Últimos agregados" → CardBadge.badge).
    5. Skeleton: `isLoading && rows.isEmpty` → 3 `SkeletonRowView` (fila de título fantasma + 4 skeletons de tarjeta) en lugar de `ProgressView("Cargando biblioteca…")`.
    6. Shelf discovery (trending/para-ti) se conserva donde está.
  - Fondo: el `ScrollView` usa `.background(MareaTheme.Colors.background)`; el root (`ThisJellyFixRootView.swift:71`) pasa de `Color(red:0.05,0.08,0.15)` a `MareaTheme.Colors.background`.
  - Handoff intacto: no tocar `onChange`/`onAppear` de `pendingNavigationItem`.

- [ ] **Step 1: Test fallido — `categoryChips`**

`LibraryModelCategoryTests`: stub con views movies+tvshows → `categoryChips` contiene 2 chips con ids correctos; stub sin views → `[]`.

- [ ] **Step 2: Ejecutar y ver fallar**

Run: `swift test --filter LibraryModelCategoryTests`
Expected: FAIL.

- [ ] **Step 3: Implementar `CategoryChip`/`categoryChips` + exponer parents**

En `load()`, guardar `moviesParent`/`seriesParent` en propiedades; computed `categoryChips`.

- [ ] **Step 4: Reconstruir `HomeView.scrollContent`**

Estructura 1-6 de arriba, manteniendo banners de sesión expirada, error state, refreshable, `onAppear` de `refreshResume` y handlers de Handoff.

- [ ] **Step 5: Fondo negro puro**

Root view background → `MareaTheme.Colors.background`; `DetailView` deja el suyo para la fase de detalle (bloque 3).

- [ ] **Step 6: Test pasar + build**

Run: `swift test && swift build` → verde.

- [ ] **Step 7: Verificación de plataforma**

Run: `xcodebuild -project thisjellyfix.xcodeproj -scheme thisjellyfix-macOS -derivedDataPath /tmp/tjf-dd build -quiet` y lo mismo con `-scheme thisjellyfix-iOS` (simulador disponible) — los `#if os` de chips/grid/hero deben compilar en macOS y iOS; tvOS/visionOS: `swift build` cubre el módulo Feature.

- [ ] **Step 8: Commit**

```bash
git add Sources/ThisJellyFixFeature/ Tests/ThisJellyFixFeatureTests/LibraryModelCategoryTests.swift
git commit -m "feat(home): streaming-style home with chips, hero carousel and see-all"
```

---

### Task 13: Tab bar flotante + tint unificado

**Files:**
- Create: `Sources/ThisJellyFixFeature/DesignSystem/FloatingTabBar.swift`
- Modify: `Sources/ThisJellyFixFeature/ThisJellyFixRootView.swift:335-408`
- Test: sin test de vista; verificación = build de plataforma

**Interfaces:**
- Consumes: `MareaTheme`, `MareaTab`.
- Produces:
  - `struct FloatingTabBar: View { @Binding var selection: MareaTab }` — píldora `Capsule` con `.ultraThinMaterial` + borde 0.5pt `glass`, iconos + labels por `MareaTab` (solo `.home/.search/.profile`), activo en `MareaTheme.Colors.accent`, flotando (`.padding(.bottom, 8)`, sombra). Disponible en **todas** las plataformas menos macOS (macOS usa sidebar).
  - `ThisJellyFixRootView.mainContent`: envuelve el `TabView` iOS 18+ — el `TabView` se queda como contenedor de `selection` pero con la barra nativa oculta (`.toolbar(.hidden, for: .tabBar)` en cada tab) y `FloatingTabBar` como overlay. iOS 17 legacy: mismo patrón con el `TabView` de `tabItem` + barra oculta. Si ocultar la barra resulta frágil en iOS 26 (Liquid Glass nativo ya da el efecto), decisión aceptada: mantener `TabView` nativo en iOS 26+ (`tabBarMinimizeBehavior`) y aplicar `FloatingTabBar` solo ≤ iOS 25 — documentar en el commit.
  - tvOS: añadir `TabView` con los 3 tabs (hoy entra directo a Home) + `FloatingTabBar` o barra nativa tvOS — decisión: `TabView` nativo de tvOS (ya trae foco y estilo); objetivo mínimo de la tarea: que tvOS tenga tabs.
  - Tint: `.tint(MareaTheme.Colors.accent)` sustituye `.red`/`.cyan` del root.

- [ ] **Step 1: Implementar `FloatingTabBar`**

Vista de arriba con tokens.

- [ ] **Step 2: Integrar en `mainContent` (iOS)**

Ocultar barra nativa + overlay; mantener `selection` y el contenido por tab idéntico.

- [ ] **Step 3: Tabs en tvOS**

`TabView` en la rama tvOS de `ThisJellyFixRootView` con Inicio/Buscar/Perfil.

- [ ] **Step 4: Tint unificado**

Sustituir los `.red`/`.cyan` de tabs/botones del root por `MareaTheme.Colors.accent`.

- [ ] **Step 5: Build de las 4 plataformas**

Run: `swift build` + `xcodebuild` para macOS e iOS (mismo patrón que Task 12 Step 7).
Expected: verde.

- [ ] **Step 6: Commit**

```bash
git add Sources/ThisJellyFixFeature/
git commit -m "feat(nav): floating glass tab bar, tvOS tabs, unified accent"
```

---

### Task 14: Verificación final de fase

- [ ] **Step 1: Suite completa**

Run: `swift build && swift test`
Expected: verde (249+ tests preexistentes + nuevos).

- [ ] **Step 2: Build Xcode 4 plataformas**

Para cada scheme (`thisjellyfix-iOS`, `thisjellyfix-macOS`, `thisjellyfix-tvOS`, `thisjellyfix-visionOS`):
`xcodebuild -project thisjellyfix.xcodeproj -scheme <scheme> -derivedDataPath /tmp/tjf-dd-<platform> build -quiet`
Expected: BUILD SUCCEEDS en las 4.

- [ ] **Step 3: Auditoría de tokens**

Run: `grep -rn "\.cyan\|\.mint\|Color(red:" Sources/ThisJellyFixFeature/ --include="*.swift" | grep -v DesignSystem`
Expected: solo coincidencias heredadas de DetailView/Player/Search que quedan para fases posteriores — anotarlas en el resumen (no bloquea).

- [ ] **Step 4: Smoke manual**

Abrir la app en simulador iOS: home con chips + hero + filas con peek + "Ver todo" → grid; sesión expirada muestra logout; pull-to-refresh funciona.

- [ ] **Step 5: Commit final si hay limpiezas**

```bash
git add -A && git commit -m "chore(phase1): final polish for foundation phase"
```
