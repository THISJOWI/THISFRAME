# AGENTS.md

Native SwiftUI Jellyfin client for iOS/macOS/tvOS/visionOS. No webviews, no third-party deps except the Google Cast SDK (iOS only). Swift 5.10, Xcode 16+.

## Layout

| Path | Owns |
|---|---|
| `Apps/<platform>/` | Thin app entry point, `Info.plist`, entitlements |
| `Sources/ThisJellyFixCore` | Domain models, Keychain, logging, subtitle/stream/handoff policies. No UI, no network |
| `Sources/ThisJellyFixNetworking` | Jellyfin API clients, server probe, playback plan, subtitles/OpenSubtitles |
| `Sources/ThisJellyFixDiscovery` | Recommenders, download queue, TMDB, *Arr clients |
| `Sources/ThisJellyFixPlayback` | AVFoundation engine, AirPlay state machine, Now Playing |
| `Sources/ThisJellyFixCast` | Google Cast wrapper (iOS only) |
| `Sources/ThisJellyFixFeature` | All SwiftUI views + `DesignSystem/` (MareaTheme tokens) |
| `Tests/<Module>Tests` | XCTest suites mirroring each module |
| `Docs/` | `specs/`, `plans/`, `COMPATIBILITY.md`; `.superpowers/sdd/` holds plan progress |

Two build systems, both real:

- **SwiftPM** (`Package.swift`) — shared modules only. No `ThisJellyFixCast`, no app targets, no assets. **Only place tests run.**
- **XcodeGen** (`project.yml` → `thisjellyfix.xcodeproj`, committed) — apps, assets, Cast, entitlements, signing.

## Commands

```bash
swift build                 # macOS host, shared modules
swift test                  # 264 XCTest cases (macOS host)
swift test --filter JellyfinLibraryClientTests   # one suite

xcodegen                    # regenerate the Xcode project after editing project.yml
scripts/iphone.sh           # build + install + launch (iPhone; DEVICE_ID=<UDID> to pick)
scripts/ipad.sh
scripts/mac.sh
scripts/appletv.sh
scripts/visionpro.sh
scripts/apple-app.sh hub    # Device Hub (pairing / selecting a destination)

xcodebuild -project thisjellyfix.xcodeproj -scheme thisjellyfix-iOS build     # also macOS/tvOS/visionOS
```

App `PRODUCT_NAME` is `THISFRAME`, so the built bundle is `THISFRAME.app` (scripts rely on this).

## Gotchas

- **Host `swift build` does not typecheck iOS/tvOS/visionOS branches.** `#if os(iOS)` / `#else` code is invisible to the host build. After touching platform-conditional code, build the affected scheme (`xcodebuild -scheme thisjellyfix-iOS`) — this has caught real regressions.
- **`swift test` only exercises macOS-host code.** The Xcode project has no test targets; do not assume iOS-only paths are covered.
- **Cast**: Google Cast SDK 4.8.6 is pinned in `project.yml` only. `Package.resolved` is gitignored → the first Xcode build needs network. Uses `GoogleCastStatic`, and the target that *links* it (app + `Cast-iOS`) needs `-ObjC`, else ObjC categories are dropped at link time → runtime "unrecognized selector". Import Cast only via `canImport`; it exists on iOS alone.
- **No CI.** The GitHub workflow was removed (commit `8966db0`). Verify locally before claiming done.
- **Secrets**: tokens live only in Keychain (`KeychainStore`, shared access group `com.thisjellyfix`). Never log them — log via `TJFLog`, which redacts `api_key`/`AccessToken` automatically.
- **visionOS**: `AVPlayer.isExternalPlaybackActive` does not exist there; code is wrapped in `#if !os(visionOS)`. Keep those guards intact.
- **Never hand-edit `thisjellyfix.xcodeproj`** — change `project.yml`, run `xcodegen`, commit the regenerated `project.pbxproj` (it is tracked).
- `build/`, `build-cli/`, `DerivedData/`, `.build/`, `.audit/` are local artifacts — do not commit.

## Conventions

- Module boundaries are hard: `Core` = domain only, `Networking` = Jellyfin API only, `Feature` = SwiftUI only.
- Design tokens live in `Sources/ThisJellyFixFeature/DesignSystem/MareaTheme.swift`; prefer them over hardcoded colors (legacy `Color(red:)`/`Color(.cyan)` still linger outside `DesignSystem`).
- Add or extend tests in `Tests/<Module>Tests` whenever you touch logic.
- Commits are conventional-ish: `feat(player): ...`, `fix(handoff): ...`. Branches: `feat/`, `fix/`, `docs/` off `main`.
- No new third-party dependencies without prior issue approval (Cast on iOS is the sole exception).
