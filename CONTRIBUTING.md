# Contributing to Yapper

Thanks for helping. Yapper is a small app with a few firm rules, so please read this before opening a pull request.

## The rules Yapper doesn't bend

These rules are the product. A change that breaks one of them won't be merged, however useful it is.

- **Free and unlimited.** No word caps, no paywalled features, no "pro" tier.
- **On-device.** Audio and text never leave the iPhone. No cloud transcription and no cloud LLM.
- **No network code** outside the model download the user starts. `ModelHub.offlineMode` stays `true` otherwise,
  and model revisions stay pinned in `Transcriber.pinnedRevisions`.
- **No accounts, analytics, ads or crash reporting** that phones home, and no third-party SDKs that do any of that.
- **The keyboard stays light.** `YapperKeyboard` never links FluidAudio or anything heavy: keyboard extensions get
  about 50 MB of memory.
- **No private API**, including tricks that jump back to the previous app automatically.
- **Yapper's style.** UI uses the tokens in `Shared/Common/Theme.swift` (flat surfaces, hairline borders, two radii,
  Inter). Don't add one-off colors or fonts.

## Getting set up

You need a Mac with Xcode 26 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and an iPhone on iOS 18 or
newer for anything involving speech (the simulator can't run the Neural Engine model).

```sh
brew install xcodegen
DEVELOPMENT_TEAM=<your team id> xcodegen generate
open Yapper.xcodeproj
```

The `.xcodeproj`, Info.plists and entitlements are generated from `project.yml` and are not committed. Edit
`project.yml`, never the generated project. To run on your own device, change the bundle IDs (`com.gluska.yapper…`)
and the App Group (`group.com.gluska.yapper`) in `project.yml` and `Shared/Common/Bridge.swift` locally, and leave
that change out of your pull request.

Before touching how the keyboard and the app talk to each other, read `Shared/Common/Bridge.swift` and
`Yapper/Session/DictationController.swift`. Most of the hard-won behavior lives there, explained in comments.

## Checks

Every push runs two GitHub Actions workflows:

- **Build** (`.github/workflows/build.yml`) compiles the app, keyboard and widgets for the simulator and runs the unit
  tests. It must pass.
- **Screenshots** (`.github/workflows/screenshots.yml`) renders every app screen and keyboard state in light and dark.
  If you change UI, download them (`gh run download <run-id> -n screenshots`) and attach before and after images to
  your pull request.

Run the tests locally with the `Yapper` scheme (Product › Test). Changes to text cleanup need a test in
`YapperTests/TextProcessorTests.swift`.

## Pull requests

- One topic per pull request. Small is better.
- Say what changed and why, and how you tested it (device model and iOS version for anything speech or keyboard
  related).
- Keep user-facing text plain and short, like the rest of the app.
- By contributing, you agree that your work is released under the [MIT License](LICENSE).

## Bugs and ideas

Use the [issue templates](https://github.com/justingluska/yapper/issues/new/choose). For security problems, don't open
an issue: see [SECURITY.md](SECURITY.md).

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
