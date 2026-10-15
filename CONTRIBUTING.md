# Contributing to ThisJellyFix

Thanks for stopping by. Small focused PRs beat big rewrites.

## Workflow

1. Open an issue first for anything beyond a typo / small fix.
2. Branch from `main`: `feat/<slug>`, `fix/<slug>`, `docs/<slug>`.
3. Regenerate project after structural changes: `xcodegen`.
4. Run before pushing:
   ```bash
   swift build
   swift test
   ```
5. PR description: what, why, how tested (device/simulator + OS). Link the issue.

## Rules

- Swift 5.10, SwiftUI native. No new third-party deps without prior issue approval (only exception today: Google Cast SDK on iOS).
- Cast code lives in `Sources/ThisJellyFixCast` and is consumed via `canImport` — never import it unconditionally from shared UI.
- Keychain for tokens. Never log tokens, passwords, or full auth headers.
- Follow existing module boundaries: `Core` = domain, `Networking` = Jellyfin API, `Discovery` = recommenders/downloads, `Feature` = SwiftUI, `Playback` = AV engine.
- Tests next to change: add/extend `Tests/<Module>Tests` when you touch logic.

## Commit style

Conventional-ish, short: `feat(player): ...`, `fix(handoff): ...`, `docs(readme): ...`.
