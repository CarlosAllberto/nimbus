# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project memory

Rules and lessons live in Claude Code auto memory, one file per topic:
`~/.claude/projects/-Users-carlos-Projetos-Treendz-nimbus-swift/memory/`
(index: `MEMORY.md`). Claude Code loads the index automatically; other agents
(Kilo, opencode) read that folder by path. Check it before non-obvious
decisions, and after fixing a bug or hitting a gotcha, add or update a topic
file there and its line in `MEMORY.md`.

File map (where each type/feature lives): `docs/memory/memory.md`. Start there
instead of rereading the tree.

## Commands

```sh
swift build          # build the app
make build            # same, via Makefile
make lint             # runs swiftlint if installed, else a no-op
make ci                # lint + build (mirrors CI)
```

There is currently no test target (`Package.swift` defines only the
`Nimbus` executable target) and no test suite in the repo.

Two build entry points must stay compatible:
- `Package.swift` — canonical SwiftPM build entry point.
- `Nimbus.xcodeproj` — Xcode entry point for development/debugging. Their
  Swift language-version settings currently differ; reconcile that only as an
  explicit, standalone change.

## Architecture

Nimbus is a macOS 14 menu-bar app (`LSUIElement`, accessory activation
policy), tray only: no main window, no sidebar, no login. All under
`Sources/Nimbus/` (flat, no submodules). `docs/memory/memory.md` lists every
file.

- **`NimbusApp.swift`** — `@main` is a plain `NSApplication` entry point (no SwiftUI
  `App`: its `Settings` scene opened a window on every launch). `AppDelegate`
  owns the status item/menu (Quick Drop, Check for Updates, Preferences,
  Quit), the Preferences `NSWindow`, the Quick Drop global hotkey (⌥⇧Q) and
  Sparkle (started only inside a real `.app`).
- **`ToolCatalog.swift`** — static catalog of the six `NimbusTool`s
  (to-webp, to-webm, ico, trim-image, convert, video-convert). Each is one Quick Drop well.
- **`QuickDropPanel.swift` / `QuickDropView.swift`** — the popup, a
  non-activating HUD panel forced to dark appearance over
  `GlassBackground(.prominent)`. Dropping on a well shows an option list
  (compression level, format or margin; Up/Down/Return/Esc handled in
  `QuickDropPanel.sendEvent`, defaults from Preferences), then per-file
  progress; results go to `~/Nimbus`.
- **`ToolRunner.swift`** — `ToolOption`/`ToolChoice` and `EngineToolRunner`,
  which maps each tool to its engine.
- **`Engines/`** — native Swift engines (`ImageCompressor`, `VideoCompressor`
  (WebM via the bundled ffmpeg), `FaviconMaker`, `ImageTrimmer`, `ImageConverter`, `VideoConverter`) on ImageIO,
  AVFoundation and libwebp. No sidecar. The one exception is
  `Resources/ffmpeg`, an LGPL-only static build (VP9 + Opus, WebM out) that
  `VideoCompressor` runs as a `Process`; rebuild it with
  `Tools/build-ffmpeg.sh` (arm64 only for now, x86_64 gap noted in the script).
  For App Store/notarized builds it must be code-signed with the app's
  identity and the sandbox inheritance entitlement
  (`com.apple.security.inherit`) — add that Run Script phase when signing.
- **Localization** — English (development language, fallback) and pt-BR, one
  String Catalog: `Resources/Localizable.xcstrings`. Every user-facing string
  is looked up with `bundle: .l10n` (`L10n.swift`: `Bundle.module` under
  SwiftPM, `Bundle.main` in the `.app`): `Text("…", bundle: .l10n)` in views,
  `String(localized: "…", bundle: .l10n)` in code (menus, window titles,
  errors). The English text is the key. To add a string: use it in code, then
  add the key to the catalog with `en` and `pt-BR` values (`translated`);
  interpolations become `%@`/`%lld` (`%%` for a literal %), counts use plural
  variations. Tool names must stay exactly two words in every language (the
  well label puts one word per line). Never translate tool ids, file
  extensions, "Nimbus", "ffmpeg" or shortcut glyphs. `swift build` binaries
  ignore the system language for resources (no `.app`), so check Portuguese
  in the Xcode-built `.app` with `-AppleLanguages "(pt-BR)"`.
- **`PreferencesView.swift`** — General (launch at login, shortcut, version)
  and Quick Drop (default option per tool) tabs.
- **`UpdateChecker.swift`** — Sparkle updater and the update indicator.
