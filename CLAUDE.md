# Yapper — free, private voice dictation for iPhone

Idea (Justin, 2026-09-24): voice dictation for iPhone like the popular cloud dictation apps, but completely free,
with no word limits, no account, no tracking, no telemetry. Speech is transcribed on the device;
nothing leaves the machine.

## Status

v0.1 built 2026-09-24: SwiftUI app + keyboard extension + widgets (Live Activity, Control Center control),
Parakeet via FluidAudio 0.17.3 on the Neural Engine. App Store name "Yapper: Voice to Text", bundle IDs
`com.gluska.yapper` (+ `.keyboard`, `.widgets`), App Group `group.com.gluska.yapper`. Read `README.md` for the
architecture, and `Shared/Common/Bridge.swift` with `Yapper/Session/DictationController.swift` before changing the
keyboard↔app handoff.

## Principles (non-negotiable unless Justin changes them)

- Free and unlimited: no word caps, no paywalled core features.
- On-device: audio and text never leave the device. No cloud transcription, no cloud LLM by default.
- No accounts, no analytics, no crash reporting that phones home.
- Types into any app via a push-to-talk hotkey (the core Wispr Flow interaction).

## Layout

- `project.yml` — XcodeGen spec; the `.xcodeproj`, Info.plists and entitlements are generated, never committed.
- `Yapper/`, `YapperKeyboard/`, `YapperWidgets/`, `Shared/`, `YapperTests/` — see README.
- `.github/workflows/build.yml` — simulator compile + unit tests on pushes that change app code (the quick check; no signing; macOS minutes bill 10x on yapper-ci).
- `.github/workflows/screenshots.yml` (on demand: `gh workflow run Screenshots --ref <branch> -R justingluska/yapper-ci`) — scheme `YapperScreens`: PNGs of the app screens and every keyboard state
  (via the never-shipped `KeyboardPreview` host app), light and dark. `gh run download <id> -n screenshots`.
  Check these before shipping any UI change, especially when you can't run Xcode yourself.
- `ci_scripts/ci_post_clone.sh` — Xcode Cloud hook: xcodegen, version from the newest `v*` tag, package resolve.

## Rules

- The keyboard never links FluidAudio or anything heavy (extension memory limit ~50 MB).
- No private API, with one exception Justin chose (2026-10-16): auto-return to the host app
  (`YapperKeyboard/HostArbiter.m`, `HostApp.swift`, `Yapper/Session/HostLauncher.swift` (LSApplicationWorkspace,
  added 2026-10-21), `Yapper/Session/ReturnLinks.swift`). It must stay guarded:
  looked up by name, nil means the swipe-back screen, never a guessed app.
- No network code outside the explicit model download. `ModelHub.offlineMode` stays true otherwise.
- The look is Yapper's own style (`Shared/Common/Theme.swift`): flat surfaces, hairline borders, Inter.

## Related

- Releases go through Xcode Cloud → TestFlight: every push to `main` tests and archives; the version comes from the
  newest `v*` tag (`ci_scripts/ci_post_clone.sh`).
- Once a version is approved its train closes: tag the next `v*` (e.g. `v1.0.1`) before the next build, or the
  upload fails with ITMS-90186/90062. Xcode Cloud stopped seeing GitHub pushes after 2026-10-16 (it still built the
  Oct 16 commit on 2026-10-24); check that the Xcode Cloud GitHub app still has access to this repo.
- Local App Store uploads: the only Apple Distribution key is in the `forge-dist` keychain, not login, so signing
  asks for that keychain's password (not the Mac password). The password noted in forge-ios's CLAUDE.md didn't work
  on 2026-10-24.
