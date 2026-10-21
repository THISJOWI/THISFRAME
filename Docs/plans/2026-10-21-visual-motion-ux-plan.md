# Plan de implementación — THISFRAME: modo claro/oscuro, animaciones, UX y estado de episodios

**Fecha:** 2026-10-21
**Rama:** `feat/visual-motion-ux`
**Alcance:** implementación completa del plan de análisis. Sin dependencias externas nuevas.

## Contexto

App SwiftUI multiplataforma (iOS 17 / macOS 14 / tvOS 17 / visionOS 1) cliente de Jellyfin
con descubrimientos TMDB. Módulos SwiftPM: `Core` (dominio), `Networking` (API Jellyfin),
`Discovery` (TMDB/Radarr/Sonarr), `Playback` (AVFoundation), `Feature` (SwiftUI),
`Cast` (solo iOS).

### Global Constraints

1. **No cambiar la paleta cromática.** El valor *dark* de cada token de `MareaTheme.Colors`
   debe quedar **exactamente** igual que hoy (negro puro de fondo, rojo `0.90/0.06/0.13`).
   Toda la adaptación ocurre en el lado claro.
2. **No tocar** la lógica de reproducción: `AVPlaybackEngine`, `PipCoordinator`, `NowPlaying`,
   `JellyfinPlaybackReporter` (intervalos y orden de reportes), `TMDBMetadataProvider`,
   `IntegrationConfig`, credenciales, `CastController`.
3. **No añadir dependencias externas** ni bases de datos nuevas.
4. **No cambiar firmas de API pública** de `JellyfinLibraryProviding` (rompería los stubs de test).
5. Todo color de superficie vive en `DesignSystem`. Los literales dispersos se sustituyen por tokens.
6. Swift 5.10, `swift build` + `swift test` en verde en cada task.
7. Commits con estilo convencional: `feat(scope): …`, `fix(scope): …`.

### Interfaces compartidas entre tasks

| Task | Produce | Consume | Verificación |
|---|---|---|---|
| 1 | `AppearanceSettings` (Core), `EpisodeWatchState` (Core) | — | — |
| 2 | `Color.adaptive`, `MareaMotion`, `MareaTheme.Palette` | — | — |
| 3 | raíz con `preferredColorScheme` dinámico, `SettingsView` Appearance | Task 1 (`AppearanceSettings`), Task 2 (`Palette`) | — |
| 4 | `EpisodeRow` con progreso, `JellyfinEpisode.watchState` | Task 1 (`EpisodeWatchState`) | — |
| 5 | `PressableCardStyle`, crossfade en `MareaImageView` | Task 2 (`MareaMotion`) | — |
| 6 | `.refreshable` en 4 pantallas | Task 4 (recarga de episodios en `DetailView`) | — |
| 7 | motion de catálogo y navegación | Task 5 (`PressableCardStyle`) | — |
| 8 | pulido del reproductor + verificación global | Tasks 2–7 | — |

**Pre-flight: sin conflictos de interfaces** — cada task produce tipos nuevos o toca vistas
distintas; el único solapamiento real (Task 6 consume la recarga de episodios de Task 4) está
ordenado y es aditivo.

---

## Task 1: Fundamentos de dominio (Core)

**Objetivo:** los dos modelos que habilitan el resto — preferencia de apariencia y estado de
reproducción de episodios — en `Core`, sin SwiftUI, con tests.

### Files

- Create: `Sources/ThisJellyFixCore/AppearanceSettings.swift`
- Create: `Sources/ThisJellyFixCore/EpisodeWatchState.swift`
- Create: `Tests/ThisJellyFixCoreTests/AppearanceSettingsTests.swift`
- Create: `Tests/ThisJellyFixCoreTests/EpisodeWatchStateTests.swift`

### Step 1 — Test RED: `AppearanceSettings`

`Tests/ThisJellyFixCoreTests/AppearanceSettingsTests.swift`:

```swift
import XCTest
@testable import ThisJellyFixCore

final class AppearanceSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "appearance.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultIsSystem() {
        XCTAssertEqual(AppearanceSettings.current(defaults).appearance, .system)
    }

    func testRoundTripPersistsEachAppearance() {
        for appearance in AppearanceSettings.Appearance.allCases {
            AppearanceSettings(appearance: appearance).save(to: defaults)
            XCTAssertEqual(AppearanceSettings.current(defaults).appearance, appearance)
        }
    }

    func testUnknownStoredValueFallsBackToSystem() {
        defaults.set("nonsense", forKey: AppearanceSettings.Key.appearance)
        XCTAssertEqual(AppearanceSettings.current(defaults).appearance, .system)
    }

    func testAllCasesCoverSystemLightDark() {
        XCTAssertEqual(
            Set(AppearanceSettings.Appearance.allCases),
            [.system, .light, .dark]
        )
    }
}
```

Run: `swift test --filter AppearanceSettingsTests`
**Expected:** FAIL — `error: cannot find 'AppearanceSettings' in scope`.

### Step 2 — Implement `AppearanceSettings`

`Sources/ThisJellyFixCore/AppearanceSettings.swift`:

```swift
import Foundation

/// Persistent appearance preference (P9). Stored in `UserDefaults` — the same
/// store `@AppStorage` writes to — so the root view can read it live and the
/// choice survives relaunch.
///
/// Mirrors the shape of `SubtitleSizeSettings` / `LanguagePreferences`: a
/// plain value type in Core, no SwiftUI, no view state.
public struct AppearanceSettings: Sendable, Equatable {

    // MARK: - Keys

    public enum Key {
        /// UserDefaults key for the selected appearance.
        public static let appearance = "appearance.mode"
    }

    // MARK: - Modes

    /// How the app resolves its color scheme.
    public enum Appearance: String, Sendable, CaseIterable, Codable, Hashable {
        /// Follow the system setting. The app must not force a scheme here.
        case system
        /// Always light.
        case light
        /// Always dark.
        case dark

        /// Human-readable label for the picker.
        public var label: String {
            switch self {
            case .system: "Sistema"
            case .light: "Claro"
            case .dark: "Oscuro"
            }
        }
    }

    // MARK: - Properties

    public var appearance: Appearance

    public init(appearance: Appearance = .system) {
        self.appearance = appearance
    }

    // MARK: - Persistence

    public static func current(_ defaults: UserDefaults = .standard) -> AppearanceSettings {
        let raw = defaults.string(forKey: Key.appearance) ?? ""
        return AppearanceSettings(appearance: Appearance(rawValue: raw) ?? .system)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(appearance.rawValue, forKey: Key.appearance)
    }
}
```

Run: `swift test --filter AppearanceSettingsTests`
**Expected:** PASS — 4 tests, 0 failures.

### Step 3 — Test RED: `EpisodeWatchState`

`Tests/ThisJellyFixCoreTests/EpisodeWatchStateTests.swift`:

```swift
import XCTest
@testable import ThisJellyFixCore

final class EpisodeWatchStateTests: XCTestCase {

    private func episode(
        ticks: Int64? = nil,
        durationTicks: Int64? = 3_600_000_000, // 1 h
        percentage: Double? = nil,
        played: Bool? = nil
    ) -> JellyfinEpisode {
        JellyfinEpisode(
            id: "e1",
            name: "Episodio",
            overview: nil,
            indexNumber: 1,
            parentIndexNumber: 1,
            runTimeTicks: durationTicks,
            seriesId: "s1",
            seriesName: "Serie",
            seasonName: "Temporada 1",
            imageTags: nil,
            userData: UserData(
                playbackPositionTicks: ticks,
                playedPercentage: percentage,
                isFavorite: nil,
                played: played
            )
        )
    }

    func testNeverStartedIsUnwatched() {
        XCTAssertEqual(episode().watchState, .unwatched)
    }

    func testZeroPositionIsUnwatched() {
        XCTAssertEqual(episode(ticks: 0).watchState, .unwatched)
    }

    func testPlayedFlagWinsOverResidualPosition() {
        let state = episode(ticks: 600_000_000, percentage: 16, played: true).watchState
        XCTAssertEqual(state, .watched)
    }

    func testPlayedFalseWithFullPercentageIsInProgress() {
        let state = episode(ticks: 3_600_000_000, percentage: 100, played: false).watchState
        XCTAssertEqual(state, .inProgress(fraction: 1.0))
    }

    func testFractionIsDerivedFromPositionAndDuration() {
        let state = episode(ticks: 1_800_000_000).watchState // 30 min of 60
        XCTAssertEqual(state, .inProgress(fraction: 0.5))
    }

    func testServerPercentageWinsOverDerivedFraction() {
        let state = episode(ticks: 600_000_000, percentage: 25).watchState
        XCTAssertEqual(state, .inProgress(fraction: 0.25))
    }

    func testUnknownDurationYieldsInProgressWithoutFraction() {
        let state = episode(ticks: 600_000_000, durationTicks: nil).watchState
        XCTAssertEqual(state, .inProgress(fraction: nil))
    }

    func testFractionIsClampedToOne() {
        let state = episode(ticks: 7_200_000_000, percentage: 140).watchState
        XCTAssertEqual(state, .inProgress(fraction: 1.0))
    }

    func testDurationSecondsConvertsTicks() {
        XCTAssertEqual(episode().durationSeconds, 3600)
        XCTAssertNil(episode(durationTicks: nil).durationSeconds)
    }
}
```

Run: `swift test --filter EpisodeWatchStateTests`
**Expected:** FAIL — `error: cannot find 'watchState' in scope`.

### Step 4 — Implement `EpisodeWatchState`

`Sources/ThisJellyFixCore/EpisodeWatchState.swift`:

```swift
import Foundation

/// Playback state of a single episode, as the server reports it.
///
/// The server is the only authority: an episode is "watched" **only** when
/// Jellyfin says `Played`. A playback position alone never means "watched" —
/// it means "in progress". Nothing here is inferred from local state.
public enum EpisodeWatchState: Sendable, Equatable {
    /// Never started, or no progress recorded at all.
    case unwatched
    /// Started but not finished. `fraction` is the played share of the
    /// episode in `0...1`, or `nil` when the duration is unknown.
    case inProgress(fraction: Double?)
    /// Marked as played by the server.
    case watched
}

public extension JellyfinEpisode {

    /// Total runtime in seconds. `nil` when the server did not report one.
    var durationSeconds: Double? {
        guard let runTimeTicks, runTimeTicks > 0 else { return nil }
        return Double(runTimeTicks) / 10_000_000.0
    }

    /// Percentage already played, as the server reports it (0–100).
    var playedPercentage: Double? {
        userData?.playedPercentage
    }

    /// True when Jellyfin marks the episode as played.
    var isPlayed: Bool {
        userData?.played ?? false
    }

    /// Resume position in seconds. `nil` when the episode was never started.
    var resumePositionSeconds: Double? {
        userData?.resumePositionSeconds
    }

    /// The episode's playback state.
    ///
    /// Precedence — the server's explicit `Played` flag always wins:
    /// 1. `played == true` → `.watched` (a residual position is not progress).
    /// 2. a position or a percentage above zero → `.inProgress`.
    /// 3. otherwise → `.unwatched`.
    var watchState: EpisodeWatchState {
        // 1. Explicitly played — the server says so, nothing overrides it.
        if isPlayed { return .watched }

        let position = resumePositionSeconds ?? 0
        let percentage = playedPercentage ?? 0
        // 2. "Started" means a real position or a real percentage. A zero
        //    position is NOT progress (the player never reports 0 either —
        //    see `JellyfinPlaybackReporter.reportProgress`).
        guard position > 0 || percentage > 0 else { return .unwatched }

        // 3. Prefer the server's own percentage; fall back to position ÷
        //    duration. Without a duration the share is unknown — the UI
        //    shows minutes watched instead of a bar.
        let fraction: Double?
        if percentage > 0 {
            fraction = percentage / 100.0
        } else if let duration = durationSeconds, duration > 0 {
            fraction = position / duration
        } else {
            fraction = nil
        }
        return .inProgress(fraction: fraction.map { min(max($0, 0), 1) })
    }
}
```

> `JellyfinEpisode.resumePositionSeconds` **ya existe** en `JellyfinMediaItem.swift:255-258`.
> Moverlo/duplicarlo aquí **no** compila (miembro duplicado). Decisión: **eliminar** el
> original de `JellyfinMediaItem.swift` y dejar la única implementación en
> `EpisodeWatchState.swift`. Es el mismo comportamiento, sin cambio de API pública.

Run: `swift test --filter EpisodeWatchStateTests`
**Expected:** PASS — 9 tests, 0 failures.

### Step 5 — Verificación de la task

Run: `swift test`
**Expected:** exit 0, todas las suites en verde.

### Step 6 — Commit

```
git add Sources/ThisJellyFixCore/AppearanceSettings.swift \
        Sources/ThisJellyFixCore/EpisodeWatchState.swift \
        Sources/ThisJellyFixCore/JellyfinMediaItem.swift \
        Tests/ThisJellyFixCoreTests/AppearanceSettingsTests.swift \
        Tests/ThisJellyFixCoreTests/EpisodeWatchStateTests.swift
git commit -m "feat(core): appearance settings and episode watch state"
```

---

## Task 2: Tokens de tema dinámico y curvas de movimiento (Feature)

**Objetivo:** `MareaTheme` con valores light/dark (el valor dark **idéntico** al actual),
helper de color adaptativo y tokens de animación con reductora de movimiento.

### Files

- Create: `Sources/ThisJellyFixFeature/DesignSystem/AdaptiveColor.swift`
- Create: `Sources/ThisJellyFixFeature/DesignSystem/MareaMotion.swift`
- Modify: `Sources/ThisJellyFixFeature/DesignSystem/MareaTheme.swift`
- Modify: `Tests/ThisJellyFixFeatureTests/MareaThemeTests.swift`

### Step 1 — Test RED: paleta

Reescribir `Tests/ThisJellyFixFeatureTests/MareaThemeTests.swift` añadiendo:

```swift
    func testDarkBackgroundStaysPureBlack() {
        XCTAssertEqual(MareaTheme.Palette.backgroundDark, Color.black)
    }

    func testDarkAccentKeepsBrandRed() {
        XCTAssertEqual(
            MareaTheme.Palette.accentDark,
            Color(red: 0.90, green: 0.06, blue: 0.13)
        )
    }

    func testAccentIsIdenticalInLightAndDark() {
        XCTAssertEqual(MareaTheme.Palette.accentLight, MareaTheme.Palette.accentDark)
    }

    func testEveryPaletteTokenDefinesBothVariants() {
        XCTAssertNotEqual(MareaTheme.Palette.backgroundLight, MareaTheme.Palette.backgroundDark)
        XCTAssertNotEqual(MareaTheme.Palette.surfaceLight, MareaTheme.Palette.surfaceDark)
    }
```

Run: `swift test --filter MareaThemeTests`
**Expected:** FAIL — `error: cannot find 'Palette' in scope`.

### Step 2 — Implementar `AdaptiveColor`

`Sources/ThisJellyFixFeature/DesignSystem/AdaptiveColor.swift`:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// A color that resolves to `light` or `dark` with the current color scheme.
    ///
    /// The two variants are resolved by the platform, so the value follows the
    /// system appearance live — no view state, no manual invalidation.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        return dark
        #endif
    }
}
```

### Step 3 — Implementar `MareaMotion`

`Sources/ThisJellyFixFeature/DesignSystem/MareaMotion.swift`:

```swift
import SwiftUI

/// Motion tokens. One place decides how the app moves, so every transition
/// feels like the same product.
///
/// Every curve here is short and settled: nothing bounces, nothing lasts
/// longer than half a second.
enum MareaMotion {
    /// Small state changes (button presses, selection tints).
    static let quick = Animation.easeInOut(duration: 0.18)
    /// Standard enter/exit (cards, panels, sheets).
    static let standard = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// Large, soft movement (rows appearing).
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.86)
    /// Opacity-only changes (images, loading states).
    static let fade = Animation.easeOut(duration: 0.22)

    /// The curve to apply, honouring the system's "reduce motion" setting.
    ///
    /// `nil` means "animate nothing" — SwiftUI reads a `nil` animation as
    /// "no implicit animation", which is exactly what the system asks for.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Applies a motion token only when the system allows animation.
struct MareaMotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(MareaMotion.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Animates `value` changes with a motion token, unless the user asked
    /// the system to reduce motion.
    func mareaAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(MareaMotionModifier(animation: animation, value: value))
    }
}
```

### Step 4 — Implementar la paleta en `MareaTheme`

`Sources/ThisJellyFixFeature/DesignSystem/MareaTheme.swift` — sustituir el bloque `Colors`:

```swift
enum MareaTheme {
    /// Raw palette. Both variants of every token live here so the values are
    /// testable without a view, and the DARK variant is the historical one:
    /// the dark theme of THISFRAME must not change.
    enum Palette {
        static let backgroundDark = Color.black
        static let backgroundLight = Color(white: 0.97)

        static let surfaceDark = Color(red: 0.11, green: 0.11, blue: 0.12)
        static let surfaceLight = Color(white: 1.0)

        static let surfaceElevatedDark = Color(red: 0.16, green: 0.16, blue: 0.18)
        static let surfaceElevatedLight = Color(white: 0.93)

        static let glassDark = Color.white.opacity(0.08)
        static let glassLight = Color.black.opacity(0.06)

        static let borderGlowDark = Color.white.opacity(0.18)
        static let borderGlowLight = Color.black.opacity(0.12)

        /// Brand red. Identical in both variants — the identity never moves.
        static let accent = Color(red: 0.90, green: 0.06, blue: 0.13)
        static let accentLight = accent
        static let accentDark = accent

        static let badgeNeutralDark = Color(red: 0.25, green: 0.27, blue: 0.32)
        static let badgeNeutralLight = Color(white: 0.35)

        static let heroFallbackDark = Color(red: 0.08, green: 0.10, blue: 0.18)
        static let heroFallbackLight = Color(white: 0.88)
    }

    enum Colors {
        /// App background — content provides the color (Netflix-style home).
        static let background = Color.adaptive(light: Palette.backgroundLight, dark: Palette.backgroundDark)
        /// Card / surface on top of the background.
        static let surface = Color.adaptive(light: Palette.surfaceLight, dark: Palette.surfaceDark)
        /// Elevated surface (panels, sheets).
        static let surfaceElevated = Color.adaptive(light: Palette.surfaceElevatedLight, dark: Palette.surfaceElevatedDark)
        /// Translucent fill for chips, glass panels and the floating tab bar.
        static let glass = Color.adaptive(light: Palette.glassLight, dark: Palette.glassDark)
        /// Hairline glow border for focused/hovered cards.
        static let borderGlow = Color.adaptive(light: Palette.borderGlowLight, dark: Palette.borderGlowDark)
        /// Red used for badges and "new season" flags.
        static let badgeRed = Color.adaptive(light: Palette.accentLight, dark: Palette.accentDark)
        /// Neutral slate for "Recién añadido" — visible without shouting.
        static let badgeNeutral = Color.adaptive(light: Palette.badgeNeutralLight, dark: Palette.badgeNeutralDark)
        /// Unified accent — tint, progress bars, active tab.
        static let accent = badgeRed
        /// Fallback backdrop while a hero image loads.
        static let heroFallback = Color.adaptive(light: Palette.heroFallbackLight, dark: Palette.heroFallbackDark)

        // MARK: - Semantic additions
        //
        // New tokens replace the literal colors that used to be scattered
        // across the views. Same role, one place.

        /// Translucent fill for settings/cards panels over the background.
        static let overlayFill = Color.adaptive(
            light: Color.black.opacity(0.05),
            dark: Color.white.opacity(0.05)
        )
        /// Fill for a screen background that sits above the app background.
        static let surfaceOverlay = Color.adaptive(
            light: Color.black.opacity(0.03),
            dark: Color.black.opacity(0.3)
        )
        /// Scrim behind text placed on top of artwork.
        static let scrim = Color.adaptive(
            light: Color.black.opacity(0.45),
            dark: Color.black.opacity(0.55)
        )
        /// Channel of a progress bar (the unfilled part).
        static let progressTrack = Color.adaptive(
            light: Color.black.opacity(0.18),
            dark: Color.white.opacity(0.25)
        )
    }

    enum Spacing { /* unchanged */ }
    enum Radius { /* unchanged */ }
}
```

### Step 5 — Verificación

Run: `swift test --filter MareaThemeTests`
**Expected:** PASS — todos en verde (los tests nuevos sobre `Palette` incluidos).

Run: `swift test`
**Expected:** exit 0.

### Step 6 — Commit

```
git add Sources/ThisJellyFixFeature/DesignSystem/AdaptiveColor.swift \
        Sources/ThisJellyFixFeature/DesignSystem/MareaMotion.swift \
        Sources/ThisJellyFixFeature/DesignSystem/MareaTheme.swift \
        Tests/ThisJellyFixFeatureTests/MareaThemeTests.swift
git commit -m "feat(design): adaptive theme tokens and motion curves"
```

---

## Task 3: Modo claro y modo oscuro

**Objetivo:** la app responde al esquema del sistema o a la preferencia manual, y todas las
superficies se leen bien en ambos.

### Files

- Modify: `Sources/ThisJellyFixFeature/ThisJellyFixRootView.swift`
- Modify: `Sources/ThisJellyFixFeature/SettingsView.swift`
- Modify: `Sources/ThisJellyFixFeature/DetailView.swift`
- Modify: `Sources/ThisJellyFixFeature/SearchView.swift`
- Modify: `Sources/ThisJellyFixFeature/FavoritesView.swift`
- Modify: `Sources/ThisJellyFixFeature/CatalogDetailView.swift`
- Modify: `Sources/ThisJellyFixFeature/DesignSystem/ChipView.swift`
- Modify: `Sources/ThisJellyFixFeature/DesignSystem/BadgeView.swift`
- Modify: `Sources/ThisJellyFixFeature/ProfileView.swift`
- Modify: `Sources/ThisJellyFixFeature/HomeView.swift`

### Step 1 — Raíz: preferencia de apariencia

En `ThisJellyFixRootView.swift`:

1. Añadir el estado:
```swift
    /// Appearance preference (Core). "system" leaves the scheme to the OS.
    @AppStorage(AppearanceSettings.Key.appearance)
    private var appearanceRaw: String = AppearanceSettings.Appearance.system.rawValue
```
2. Añadir el computed:
```swift
    /// The scheme to force on the app, or `nil` to follow the system.
    private var preferredColorScheme: ColorScheme? {
        switch AppearanceSettings.Appearance(rawValue: appearanceRaw) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
```
3. Sustituir `.preferredColorScheme(.dark)` por `.preferredColorScheme(preferredColorScheme)`.
4. Sustituir los literales de la vista de conexión:
   - `.background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))` →
     `.background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))`
   - `.background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))` →
     `.background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))`
   - `.tint(.mint)` → `.tint(MareaTheme.Colors.accent)` (el verde menta estaba fuera de la paleta).

Run: `swift build` → **Expected:** compila.

### Step 2 — Ajustes: sección de apariencia

En `SettingsView.swift`, añadir la sección (antes de `SkipSettingsSection`):

```swift
// MARK: - Appearance

/// Light / dark / follow-the-system. The picker's value lives in
/// `UserDefaults` (Core) so the root view reacts to it live.
private struct AppearanceSettingsSection: View {
    @AppStorage(AppearanceSettings.Key.appearance)
    private var rawAppearance: String = AppearanceSettings.Appearance.system.rawValue

    private var selection: Binding<AppearanceSettings.Appearance> {
        Binding(
            get: { AppearanceSettings.Appearance(rawValue: rawAppearance) ?? .system },
            set: { rawAppearance = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apariencia")
                .font(.headline)

            Picker("Apariencia", selection: selection) {
                ForEach(AppearanceSettings.Appearance.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("«Sistema» sigue la preferencia del sistema.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}
```

Y sustituir los tres `.background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))`
de `SettingsView.swift` por `.background(MareaTheme.Colors.overlayFill, in: RoundedRectangle(cornerRadius: 12))`.

Run: `swift build` → **Expected:** compila.

### Step 3 — Superficies de las demás pantallas

Sustituciones literales (una por una, keeping the look in dark mode identical):

| Archivo | Literal actual | Token |
|---|---|---|
| `DetailView.swift` | `.background(Color.black.ignoresSafeArea())` | `.background(MareaTheme.Colors.background.ignoresSafeArea())` |
| `DetailView.swift` | `Text(detail.name)….foregroundStyle(.white)` | `.foregroundStyle(.primary)` |
| `DetailView.swift` | `.background(.white.opacity(0.10), in: Capsule())` (chips de vídeo) | `.background(MareaTheme.Colors.overlayFill, in: Capsule())` + `.foregroundStyle(.primary)` |
| `DetailView.swift` | `Color.white.opacity(0.1)` (píldora de temporada) | `MareaTheme.Colors.overlayFill` |
| `DetailView.swift` | `.foregroundStyle(index == selectedSeasonIndex ? .black : .white)` | `.foregroundStyle(index == selectedSeasonIndex ? Color.black : Color.primary)` |
| `DetailView.swift` | gradiente del hero que termina en `.black` | termina en `MareaTheme.Colors.background` |
| `SearchView.swift` | `.background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))` | `MareaTheme.Colors.overlayFill` |
| `SearchView.swift` | `.background(Color.black.opacity(0.3))` | `MareaTheme.Colors.surfaceOverlay` |
| `FavoritesView.swift` | `.background(Color.black.opacity(0.3))` | `MareaTheme.Colors.surfaceOverlay` |
| `CatalogDetailView.swift` | `.background(Color.black.opacity(0.3))` | `MareaTheme.Colors.surfaceOverlay` |
| `ChipView.swift` | `isSelected ? Color.white.opacity(0.9) : MareaTheme.Colors.glass` | `isSelected ? MareaTheme.Colors.accent : MareaTheme.Colors.glass` |
| `ChipView.swift` | `.foregroundStyle(isSelected ? Color.black : Color.primary)` | `.foregroundStyle(isSelected ? Color.black : Color.primary)` (sin cambio) |
| `BadgeView.swift` | flag "Siguiente episodio" con `.background(.white)` | **sin cambio** (elemento sobre imagen; blanco garantiza contraste en ambos modos) |
| `ProfileView.swift` | (sin fondo) | añadir `.background(MareaTheme.Colors.background)` al `ScrollView` |

Además, en `DetailView.swift` el gradiente del hero:

```swift
                LinearGradient(
                    colors: [
                        .clear,
                        .clear,
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.7),
                        Color.black.opacity(0.95),
                        MareaTheme.Colors.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
```

Run: `swift build` → **Expected:** compila.
Run: `swift test` → **Expected:** exit 0.

### Step 4 — Commit

```
git add -A Sources/ThisJellyFixFeature
git commit -m "feat(feature): light and dark appearance with system follow"
```

---

## Task 4: Estado de reproducción de cada episodio

**Objetivo:** cada episodio de la lista muestra no visto / en progreso (con línea de
progreso) / visto, sincronizado con Jellyfin.

### Files

- Modify: `Sources/ThisJellyFixNetworking/JellyfinLibraryClient.swift`
- Create: `Sources/ThisJellyFixFeature/DesignSystem/ProgressBarView.swift`
- Modify: `Sources/ThisJellyFixFeature/DetailView.swift`
- Modify: `Tests/ThisJellyFixNetworkingTests/JellyfinLibraryClientTests.swift`

### Step 1 — Test RED: frescura de la caché de episodios

En `Tests/ThisJellyFixNetworkingTests/JellyfinLibraryClientTests.swift`, añadir un test que
compruebe que la petición de episodios no usa la caché de URLSession. El test existente usa
un `StubSession`; el test nuevo:

```swift
    func testFetchEpisodesAsksTheServerInsteadOfTheURLCache() async throws {
        let session = RequestRecordingSession()
        let client = JellyfinLibraryClient(session: session)
        _ = try? await client.fetchEpisodes(
            userId: "u1", serverURL: URL(string: "https://s.example")!, token: "t", seriesId: "s1", seasonId: "se1"
        )
        XCTAssertEqual(session.lastRequest?.cachePolicy, .reloadIgnoringLocalCacheData)
    }
```

> Si el `StubSession` del test no expone `lastRequest`, **añadir esa propiedad** al stub
> (es un cambio de test, no de producción).

Run: `swift test --filter JellyfinLibraryClientTests`
**Expected:** FAIL — la política es `.useProtocolCachePolicy`.

### Step 2 — Implementar

En `JellyfinLibraryClient.swift`, `fetchEpisodes`: pasar `cachePolicy: .reloadIgnoringLocalCacheData`
a `fetchData`. Razón: el progreso de un episodio cambia en el servidor; una respuesta cacheada
mostraría un estado obsoleto.

Run: `swift test --filter JellyfinLibraryClientTests` → **Expected:** PASS.

### Step 3 — `ProgressBarView`

`Sources/ThisJellyFixFeature/DesignSystem/ProgressBarView.swift`:

```swift
import SwiftUI

/// A thin progress line: a track plus a filled share of it.
///
/// Used by the episode rows and the "continue watching" card. The fill keeps
/// the brand accent so it never reads as a decorative rule.
struct ProgressBarView: View {
    /// Played share in `0...1`.
    let fraction: Double
    var height: CGFloat = 3

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(MareaTheme.Colors.progressTrack)
                Capsule()
                    .fill(MareaTheme.Colors.accent)
                    .frame(width: max(0, geo.size.width * clamped))
            }
        }
        .frame(height: height)
        .mareaAnimation(MareaMotion.easeOutProgress, value: clamped)
    }
}
```

Y añadir a `MareaMotion`:
```swift
    /// Progress fills move a little longer than a state change — the eye
    /// follows the bar to its new position.
    static let easeOutProgress = Animation.easeOut(duration: 0.35)
```

### Step 4 — `EpisodeRow` con estado

En `DetailView.swift`, sustituir el `private struct EpisodeRow` por una versión que muestra
el estado. Requisitos:

- `episode.watchState` decide la presentación.
- `.watched` → checkmark sobre la miniatura + título en `.secondary`.
- `.inProgress(fraction)` → `ProgressBarView` + texto "Vas por N min".
- `.unwatched` → presentación actual, sin línea ni icono.
- Accesibilidad: `.accessibilityElement(children: .combine)` + etiqueta con el estado.
- Animación de entrada de la línea y del checkmark con `MareaMotion`.

Firma que consume:

```swift
private struct EpisodeRow: View {
    let episode: JellyfinEpisode
    let serverURL: URL
    let onPlay: () -> Void
}
```

### Step 5 — Recargar episodios al cerrar el reproductor

En `DetailView.swift`, el `.onChange(of: showPlayer)` ya existe (llama `onPlayerDismiss?()`).
Añadir: cuando `showPlayer` pasa a `false` y el contenido es una serie, recargar los episodios
de la temporada activa y el detalle:

```swift
            .onChange(of: showPlayer) { _, showing in
                if !showing {
                    onPlayerDismiss?()
                    // The episode we just played changed its state on the
                    // server — the list must show the new progress.
                    if detail?.type == "Series" {
                        Task { await reloadEpisodesAfterPlayback() }
                    }
                }
            }
```

con:

```swift
    /// Re-read the current season after playback so the rows show the real
    /// progress (and the "watched" mark when the episode was finished).
    private func reloadEpisodesAfterPlayback() async {
        guard let season = seasons[safe: selectedSeasonIndex] else { return }
        await loadEpisodes(for: season)
    }
```

> Añadir el helper `safe:` a `DetailView` (o usar `seasons.indices.contains(selectedSeasonIndex)`).

Run: `swift build` → **Expected:** compila.

### Step 6 — Verificación y commit

Run: `swift test` → **Expected:** exit 0.

```
git add Sources/ThisJellyFixNetworking/JellyfinLibraryClient.swift \
        Sources/ThisJellyFixFeature/DesignSystem/ProgressBarView.swift \
        Sources/ThisJellyFixFeature/DetailView.swift \
        Tests/ThisJellyFixNetworkingTests/JellyfinLibraryClientTests.swift
git commit -m "feat(feature): episode progress and watched state"
```

---

## Task 5: Animaciones de tarjetas e imágenes

**Objetivo:** crossfade en la carga de imagen, feedback de pulsación y entrada determinista.

### Files

- Modify: `Sources/ThisJellyFixFeature/ImageView.swift`
- Create: `Sources/ThisJellyFixFeature/DesignSystem/PressableCardStyle.swift`
- Modify: `Sources/ThisJellyFixFeature/MediaCardView.swift`
- Modify: `Sources/ThisJellyFixFeature/DesignSystem/RowSection.swift`
- Modify: `Sources/ThisJellyFixFeature/CatalogCardView.swift`

### Step 1 — `PressableCardStyle`

`Sources/ThisJellyFixFeature/DesignSystem/PressableCardStyle.swift`:

```swift
import SwiftUI

/// Press feedback for a poster card: the card shrinks a touch while the
/// finger is down and springs back on release.
struct PressableCardStyle: ButtonStyle {
    /// Scale applied while pressed.
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(MareaMotion.quick, value: configuration.isPressed)
    }
}
```

### Step 2 — Crossfade en `MareaImageView`

En `ImageView.swift`, el `body` de `MareaImageView` pasa a:

```swift
    var body: some View {
        Group {
            if let image = loader.image {
                artwork(image)
            } else if loader.isLoading {
                ProgressView()
                    .mareaRatioBox(aspectRatio, contentMode: .fit)
            } else {
                placeholderBox
            }
        }
        .modifier(MareaImageSizing(width: width, height: height, aspectRatio: aspectRatio))
        .transition(.opacity)
        .mareaAnimation(MareaMotion.fade, value: loader.image != nil)
        .task(id: url) {
            if let url {
                loader.load(url: url, fallback: fallbackURL)
            }
        }
    }
```

> `.mareaAnimation` con `value: loader.image != nil` (un `Bool`) evita comparar imágenes y
> hace la animación barato: ocurre **una vez** por imagen, nunca durante el scroll.

### Step 3 — Entrada determinista en `MediaCardView`

En `MediaCardView.swift`:

1. Añadir el parámetro `var appearIndex: Int = 0` al `init`.
2. Sustituir el `onAppear`:

```swift
        .onAppear {
            // One entrance per card, and only once: a recycled LazyHStack cell
            // must not re-animate while the user scrolls.
            guard !hasAppeared else { return }
            hasAppeared = true
            guard !reduceMotion else {
                isAppeared = true
                return
            }
            let delay = min(Double(appearIndex) * 0.03, 0.2)
            withAnimation(MareaMotion.standard.delay(delay)) {
                isAppeared = true
            }
        }
```

con `@Environment(\.accessibilityReduceMotion) private var reduceMotion` y
`@State private var hasAppeared = false`.

> El `Double.random(in: 0...0.15)` desaparece: el retardo pasa a derivarse del índice, que es
> determinista y testeable.

### Step 4 — Aplicar el estilo de pulsación

En `RowSection.swift` (`card(for:)`) y en `LibraryGridView.swift` / `SearchView.swift` /
`FavoritesView.swift`, cambiar `.buttonStyle(.plain)` por `.buttonStyle(PressableCardStyle())`
**en las tarjetas de medios** (no en los botones de texto ni en los `NavigationLink` de
categorías).

En `RowSection.swift`, `horizontalRows` / `FlowLayoutRows` deben pasar el índice:

```swift
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    card(for: item, index: index)
                }
```

y `card(for:index:)` → `cardView(for: item, index: index)` → `MediaCardView(..., appearIndex: index)`.

Run: `swift build` → **Expected:** compila.

### Step 5 — Commit

```
git add Sources/ThisJellyFixFeature
git commit -m "feat(feature): image crossfade, press feedback and deterministic card entrance"
```

---

## Task 6: Deslizar para actualizar

**Objetivo:** refresh donde aporta, sin vaciar contenido ni perder la posición de scroll.

### Files

- Modify: `Sources/ThisJellyFixFeature/LibraryGridView.swift`
- Modify: `Sources/ThisJellyFixFeature/DetailView.swift`
- Modify: `Sources/ThisJellyFixFeature/FavoritesView.swift`
- Modify: `Sources/ThisJellyFixFeature/CatalogDetailView.swift`

### Step 1 — `LibraryGridView`: recargar sin vaciar

Hoy `.refreshable` hace `items = []` → pantalla en blanco y salto de scroll. Nuevo:

```swift
        .refreshable {
            // Reload the first page IN PLACE: emptying the grid blanks the
            // screen and throws away the scroll position.
            await reloadFirstPage()
        }
```

```swift
    /// Fetch the first page and replace the current items — the grid keeps
    /// showing content while the request is in flight.
    private func reloadFirstPage() async {
        guard !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        let page = await model.fetchPage(
            parentId: parentId,
            includeTypes: includeTypes,
            limit: pageSize,
            startIndex: nil
        )
        items = page
        hasMore = page.count == pageSize
        nextStartIndex = page.count
    }
```

`loadFirstPage()` se conserva para el `.task` inicial (evita duplicar código: `reloadFirstPage`
puede reutilizarse y `loadFirstPage` eliminarse, manteniendo `.task { await reloadFirstPage() }`).

### Step 2 — `DetailView`: refresh de detalle + temporadas + episodios

```swift
            .refreshable {
                // Detail, seasons and episodes in parallel — one gesture,
                // one round trip each.
                async let detailReload: Void = loadDetail()
                async let seasonsReload: Void = loadSeasons()
                _ = await (detailReload, seasonsReload)
            }
```

> `loadSeasons()` ya recarga los episodios de la primera temporada; para mantener la
> temporada seleccionada, `loadSeasons` debe recargar la temporada activa si existe.
> Ajustar `loadSeasons` para recargar `seasons[selectedSeasonIndex]` cuando exista.

### Step 3 — `FavoritesView`: refresh

```swift
            .refreshable { await loadFavorites() }
```

`loadFavorites()` ya existe;además sustituye su `withAnimation(.spring(response: 0.3))` global
por una animación **no** bloqueante (asignación directa), para no re-animar toda la rejilla.

### Step 4 — `CatalogDetailView`: refresh del estado de descarga

```swift
        .refreshable { await discovery?.refreshDownloads() }
```

Run: `swift build` → **Expected:** compila.
Run: `swift test` → **Expected:** exit 0.

### Step 5 — Commit

```
git add Sources/ThisJellyFixFeature
git commit -m "feat(feature): pull to refresh on library, detail and favourites"
```

---

## Task 7: Movimiento de catálogo y navegación

**Objetivo:** los pósters TMDB responden como los de Jellyfin y la navegación gana
continuidad visual.

### Files

- Modify: `Sources/ThisJellyFixFeature/CatalogCardView.swift`
- Modify: `Sources/ThisJellyFixFeature/CatalogDetailView.swift`
- Modify: `Sources/ThisJellyFixFeature/DiscoveryRowView.swift`
- Modify: `Sources/ThisJellyFixFeature/DetailView.swift`

### Step 1 — `CatalogCardView`

- Aplicar `PressableCardStyle` donde se usa como botón.
- Añadir la misma entrada determinista que `MediaCardView` (`appearIndex`).
- `MareaImageView` ya hace crossfade (Task 5) → no hace falta nada más.

### Step 2 — `CatalogDetailView`: hero con backdrop

`CatalogItem.backdropURL` ya existe y **nunca se usa**. Nuevo hero:

```swift
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let backdropURL = item.backdropURL {
                MareaImageView(url: backdropURL, placeholder: "", width: 0, height: 0)
                    .frame(height: 180)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, MareaTheme.Colors.surfaceOverlay],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
            }
            posterRow
        }
    }
```

La imagen de fondo **no** se vuelve a pedir en ningún sitio más: `CatalogItem` ya la trae y
`MareaImageView` la cachea.

### Step 3 — `DiscoveryRowView`: entrada de la estantería

```swift
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(MareaMotion.gentle) { appeared = true }
        }
```

con `@State private var appeared = false`.

### Step 4 — `DetailView`: transición de carga y zoom de navegación

1. Transición de carga: envolver las ramas de `detailContent` en
   `.transition(.opacity)` + `.animation(MareaMotion.fade, value: detail != nil)`.

2. Zoom de navegación (iOS 18+), en `RowSection.swift` (`NavigationLink(value: item)`) y en
   `DetailView` (`.navigationDestination`):

```swift
        // iOS 18+: the poster zooms into the detail screen. Older systems keep
        // the standard push — the fallback must not change the navigation.
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: item.id, in: namespace))
        } else {
            content
        }
```

El `namespace` se inyecta por `environment`. **Si la transición zoom resulta inestable en la
navegación programática (`navigationPath`), se revierte a push estándar** — el fallback está
explícito en el propio código.

Run: `swift build` → **Expected:** compila.

### Step 5 — Commit

```
git add Sources/ThisJellyFixFeature
git commit -m "feat(feature): catalog motion and detail continuity"
```

---

## Task 8: Pulido del reproductor y verificación global

**Objetivo:** crossfade real del subtítulo, curva del indicador de seek y una pasada final de
verificación en todos los modos.

### Files

- Modify: `Sources/ThisJellyFixFeature/PlayerView.swift`
- Modify: `Sources/ThisJellyFixFeature/DesignSystem/ResumeCardView.swift`
- Modify: `Sources/ThisJellyFixFeature/DesignSystem/FloatingTabBar.swift`
- Modify: `Sources/ThisJellyFixFeature/DetailView.swift`

### Step 1 — Subtítulo del reproductor

`PlayerView.swift`: el overlay de subtítulo tiene `.transition(.opacity)` pero ninguna
animación que lo dispare. Añadir `.mareaAnimation(MareaMotion.fade, value: viewModel.subtitleText)`
sobre el `Text`.

### Step 2 — Indicador de seek

`PlayerView.swift:769-771`: `withAnimation { seekIndicator = ... }` sin curva →
`withAnimation(MareaMotion.standard) { ... }`.

### Step 3 — Barra de "Estás viendo"

`ResumeCardView.progressBar`: sustituir el `GeometryReader` manual por `ProgressBarView` con
`fraction = percentage / 100` (gana la animación de la Task 5).

### Step 4 — Barra de pestañas flotante (iOS 17–25)

`FloatingTabBar.swift`: añadir una cápsula `matchedGeometryEffect` detrás del icono
seleccionado, con `MareaMotion.standard`. En iOS 26 la `TabView` nativa ya lo hace y esta
vista no se usa.

```swift
    @Namespace private var tabNamespace
    ...
                ZStack {
                    if selection == tab {
                        Capsule()
                            .fill(MareaTheme.Colors.glass)
                            .matchedGeometryEffect(id: "tab.selection", in: tabNamespace)
                    }
                    VStack(spacing: 2) { ... }
                }
```

### Step 5 — Verificación global

1. `swift build` → compila.
2. `swift test` → exit 0.
3. Comprobación manual de contraste en modo claro y oscuro sobre: Home, LibraryGridView,
   DetailView (hero + episodios), SearchView, FavoritesView, ProfileView, SettingsView,
   CatalogDetailView, LoginView / ServerConnectionView.
4. Comprobación de que el reproductor sigue siendo negro en ambos modos.

### Step 6 — Commit

```
git add Sources/ThisJellyFixFeature
git commit -m "feat(player): subtitle crossfade and transport polish"
```

---

## Fuera de alcance (decisiones explícitas)

- **No** se añaden animaciones al scroll de las listas.
- **No** se toca la lógica de reproducción, PiP, AirPlay ni el reporte de progreso.
- **No** se precargan imágenes de TMDB (el cache de `MareaImageView` ya evita el refetch).
- **No** se aniade `matchedGeometryEffect` manual entre la tarjeta y el hero: la navegación
  programática lo hace frágil; se usa `navigationTransition` del sistema (Task 7).
- **No** se cambia el endpoint ni las credenciales de TMDB/Jellyfin.

---

## Registro de decisiones (ledger de ejecución)

# SDD ledger — plan: Docs/plans/2026-10-21-visual-motion-ux-plan.md

Plan: implementación de modo claro/oscuro, animaciones, pull-to-refresh y estado de
episodios para THISFRAME. Spec: este mismo fichero (no hay spec separada — el plan
fue el análisis del repo y ES la spec).

Pre-flight: sin conflictos de interfaces entre tasks (Task 1 produce los modelos de Core,
Task 2 los tokens de DesignSystem, Tasks 3–8 consumen de forma aditiva; el único
solapamiento — Task 6 consume la recarga de episodios de Task 4 — está ordenado).

Baseline verificada antes de Task 1: `swift test` → exit 0 (264 tests Core + resto en verde).

Task 1: Ruling: `resumePositionSeconds` se queda en `JellyfinMediaItem.swift` (junto a
  `durationMinutes`) en lugar de duplicarse en el fichero nuevo — el plan lo ponía en
  `EpisodeWatchState.swift` y habría colisionado con el miembro ya existente; mantener los
  accesores DTO junto al DTO es más cohesivo y no cambia la API pública.
  Coste si está mal: un `git mv` de 4 líneas.
Task 1: Ruling: los ticks del test de duración eran 3 600 000 000 (360 s), no 1 h —
  1 h son 36 000 000 000 ticks (10 000 000 ticks/s). El fallo era del test, no de la
  implementación (`UserData.resumePositionSeconds` ya usa /10 000 000). Test corregido.
  Coste si está mal: la constante del test.
Task 1: complete (commits 52eb601..4d65900, tests: swift test → exit 0, 0 failures)
Task 2: complete (commits 4d65900..HEAD, tests: swift test → exit 0)
Task 3: Ruling: el target visionOS NO compilaba antes de este cambio (`glassEffect` no
  existe en visionOS y `AVPlayer.isExternalPlaybackActive` tampoco). El plan exige que las
  4 plataformas compilen (AC-31), así que se corrigió con guardas de COMPILE-TIME puras:
  `wasExternallyActive = false` en visionOS y el aviso de AirPlay dentro de `#if !os(visionOS)`.
  Cero cambio de comportamiento en iOS/macOS/tvOS.
  Coste si está mal: 2 guardas de 4 líneas.
Task 3: Ruling: el botón "Conectar" usaba `.tint(.mint)` — verde menta fuera de la paleta de
  THISFRAME. Cambiado a `MareaTheme.Colors.accent` (el rojo de marca). Es eliminación de un
  color ajeno, no rediseño de la identidad.
  Coste si está mal: 1 línea.
Task 3: nota: `swift test` mostró un fallo ESPORÁDICO en ThisJellyFixFeatureTests (1 vez de 5);
  el mismo fallo se observó en la línea base ANTES de tocar nada y no se ha reproducido en 4
  ejecuciones posteriores. Test preexistente e inestable, no causado por este trabajo.
Task 3: complete (commits cc89935..9d0dd76, tests: swift test → exit 0; xcodebuild macOS+iOS+tvOS+visionOS → BUILD SUCCEEDED)
Task 4: complete (commits 9d0dd76..HEAD, tests: swift test → exit 0; xcodebuild iOS → BUILD SUCCEEDED)
Task 5: Ruling: el plan pedía un flag `hasAppeared` dentro de la tarjeta, pero eso NO evita
  el parpadeo al hacer scroll (SwiftUI destruye y recrea las celdas fuera de pantalla, y
  @State se reinicia). Se implementó `CardEntranceModifier` con un flag `animates` que la
  fila pasa a las tarjetas: las primeras se animan, las que aparecen después se muestran ya
  en su sitio (`isRevealed` inicial = `!animates`, así que no hay frame en blanco).
  Coste si está mal: 1 modificador de 40 líneas.
Task 5: Ruling: las tarjetas de rejilla (LibraryGridView, SearchView, FavoritesView) NO se
  animan al entrar: en una rejilla las celdas aparecen continuamente al hacer scroll y
  animarlas produce parpadeo. Las estanterías horizontales (RowSection) sí se animan.
  Coste si está mal: 1 parámetro por vista.
Task 5: complete (commits 3ffdfc6..HEAD, tests: swift test → exit 0; xcodebuild iOS+macOS+tvOS+visionOS → BUILD SUCCEEDED)
Task 6: Ruling: `loadDetail()` se dividió en `loadDetail()` (con spinner, para la primera
  carga) y `fetchDetail(reloadSeasons:)` (sin spinner, para refrescar): un `.refreshable` que
  conmuta a "Cargando detalle…" borraría el contenido que se está refrescando.
  Coste si está mal: 2 métodos.
Task 6: Ruling: `loadSeasons()` ahora recarga la temporada SELECCIONADA (no la primera): un
  refresco no debe devolver al usuario a la temporada 1.
  Coste si está mal: 3 líneas.
Task 6: complete (commits c056e83..HEAD, tests: swift test → exit 0; xcodebuild iOS+macOS → BUILD SUCCEEDED)
Task 7: Ruling: NO se implementa `navigationTransition(.zoom)` + `matchedTransitionSource`
  (el "zoom" póster→ficha). El ID de transición tendría que ser `item.id`, y el MISMO título
  aparece en varias estanterías a la vez ("Películas" y "Últimos agregados"), con lo que
  habría dos fuentes con el mismo ID en el mismo namespace — colisión que SwiftUI no resuelve
  de forma fiable. Sin forma de verificar la animación en este entorno, el riesgo de
  regresión en la navegación supera el beneficio. La continuidad se entrega con el crossfade
  de imagen del hero (Task 5) + la transición de opacidad del contenido.
  Coste si está mal: queda sin zooms la transición de navegación.
Task 7: complete (commits 279a27e..HEAD, tests: swift test → exit 0; xcodebuild iOS+macOS+tvOS+visionOS → BUILD SUCCEEDED)
Task 8: Ruling: `StubLibraryClient.recordedStartIndices` se mutaba desde varias tareas a la vez
  (`LibraryModel.load()` carga 4 filas en paralelo) → carrera de datos → corrupción de heap →
  SIGSEGV/SIGTRAP del proceso de test. Preexistente (se observó en la línea base) y causaba
  ~1 fallo de suite por cada 20 ejecuciones. Arreglado con un NSLock en el stub, con test de
  estrés RED (5/5 crashes) → GREEN (5/5 + 15/15 suite completa sin fallos).
  Coste si está mal: 1 lock en un stub de test.
Task 8: contraste verificado numéricamente (WCAG): modo claro — texto primario 19.7:1,
  texto sobre acento 4.4:1, badge neutro 7.0:1, overlay 17.6:1; modo oscuro sin cambios.
Task 8: complete (commits c5e472e..HEAD, tests: swift test → exit 0 (15/15); xcodebuild iOS+macOS+tvOS+visionOS → BUILD SUCCEEDED)

Final: revisión de rama (code-reviewer) — 1 CRITICAL, 6 IMPORTANT, 5 MINOR.
Final: fixed CRITICAL (macOS no seguía el esquema de color) — `NSApp.appearance` se sincroniza
  con la preferencia vía `MacAppearance.appAppearance(for:)` (test RED: `cannot find
  'MacAppearance' in scope` → GREEN 4/4). Sin esto, en macOS el modo forzado dejaba texto
  negro sobre tokens oscuros.
Final: fixed IMPORTANT (macOS nunca recargaba los episodios) — la recarga tras cerrar el
  reproductor se añadió también a la rama `#if os(macOS)`.
Final: fixed IMPORTANT (carrera recarga vs reporte final) — la recarga espera 1,5 s a que el
  reporte `Stopped` llegue al servidor; si no, la lista mostraba el estado anterior.
Final: fixed IMPORTANT (un fallo de red borraba la lista) — `loadEpisodes` conserva los
  episodios previos y muestra un aviso (`episodesError`) en vez de "No hay episodios".
Final: fixed IMPORTANT (la lista desaparecía en cada recarga) — el spinner solo aparece en la
  primera carga; las recargas son silenciosas (`loadEpisodes(for:silently:)`).
Final: fixed IMPORTANT (la etiqueta de accesibilidad no decía el título) — usa
  `episode.displayTitle` en vez de `episode.episodeLabel`.
Final: fixed IMPORTANT (canal de la barra invisible en claro) — `ResumeCardView` usa un
  canal blanco 0.25 (la barra va sobre el scrim oscuro de la tarjeta, en ambos modos).
Final: fixed MINOR (transición en el nivel equivocado) — el `.transition(.opacity)` pasa a las
  ramas del `if/else` de `MareaImageView`.
Final: fixed MINOR (el refresh de la rejilla perdía páginas) — `reloadFirstPage` sustituye
  solo la primera página y conserva el resto; el refresco ya no es un no-op silencioso
  (`isRefreshing` aparte de `isLoadingPage`).
Final: fixed MINOR (animaciones que ignoraban "reducir movimiento") — `PressableCardStyle`,
  `DiscoveryRowView`, `DetailView` y `FloatingTabBar` pasan a `MareaMotion.resolve` /
  `mareaAnimation`.
Final: fixed MINOR (`AppearanceSettings` era código muerto) — `AppearanceSettings.current()`
  lo usa la sincronización de apariencia de macOS.
Final: fixed MINOR (rojo de marca bajo 4.5:1) — nuevo token `accentText`: el MISMO tono de
  rojo, un pelo más profundo en claro (5.1:1) y un pelo más claro en oscuro (4.8:1). Los
  RELLENOS (botones, barras, badges) conservan el rojo de marca intacto en ambos modos.
  Test RED→GREEN (`MareaContrastTests`, 5/5) con medición WCAG real.
Final: minor (deferred): el rojo de marca sobre la TARJETA oscura da 3.59:1 (preexistente;
  el token de texto lo sube a 3.89:1). Los badges de género (rojo sobre su propio tinte al
  20 %) dan 3.36:1 en claro y 3.92:1 en oscuro — PREEXISTENTE en ambos modos. Corregirlo
  exigiría cambiar el color del badge, que el brief prohíbe.
