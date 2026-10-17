# File map

Where things live, so you can open the right file instead of rereading the
tree. Line counts are approximate (2026-09-18). Update this file when you add,
rename or split a file.

## Entry points and build

- `Package.swift`: SwiftPM target `Nimbus` (macOS 14, Swift tools 6.0), depends on Sparkle and libwebp (`libwebp-Xcode`).
- `Nimbus.xcodeproj/project.pbxproj`: Xcode build. A new `.swift` file needs both pbxproj entries; Engines files live in an `Engines` group, libwebp is a package product.
- `Makefile`: `make build`, `make lint`, `make ci`.
- `.github/workflows/ci.yml`: CI build, versioned release, Homebrew cask.
- `Sources/Nimbus/Info.plist` (incl. `CFBundleLocalizations` en, pt-BR), `Nimbus.entitlements`, `Resources/` (AppIcon.icns, TrayIcon.png, ffmpeg, `Localizable.xcstrings`).

## App shell (`Sources/Nimbus/`)

Tray-only app: no main window, no sidebar, no login. Quick Drop is the whole UI.

- `NimbusApp.swift` (~200): `@main NimbusMain` (plain `NSApplication`, no SwiftUI scene), `AppDelegate` (status item, menu, Preferences window, Quick Drop hotkey, Sparkle).
- `L10n.swift` (~30): `Bundle.l10n` (SwiftPM `Bundle.module` / app `Bundle.main`) and `l10nSelfCheck()`. Localization: `Resources/Localizable.xcstrings` (en + pt-BR). Add a string: use `Text("key", bundle: .l10n)` or `String(localized: "key", bundle: .l10n)` (English text is the key), add the key with en + pt-BR `translated` values (plural variations for counts); tool names stay two words.
- `GlassBackground.swift` (90): Liquid Glass on macOS 26, vibrancy fallback.
- `PreferencesView.swift` (~150): tabs General (launch at login, shortcut, version/update) and Quick Drop (default option per tool: compression level, convert format, favicon margin).
- `UpdateChecker.swift` (80): Sparkle `AppUpdater`, `UpdateIndicator`.
- `LaunchAtLogin.swift` (37): `SMAppService` toggle.
- `GlobalHotKey.swift` (~110): `QuickDropShortcut` (⌥⇧Q), Carbon hotkey wrapper.

## Tools and Quick Drop

- `ToolCatalog.swift` (~20): `NimbusTool`, `ToolCatalog` (the six tools: to-webp, to-webm, ico, trim-image, convert, video-convert).
- `ToolRunner.swift` (~100): `ToolOption`, `ToolChoice` (rows of the option list, Preferences default), `ToolRunner` protocol, `EngineToolRunner` (tool id -> engine).
- `FileAcceptance.swift` (77): accepted `UTType`s and size limits per input kind.
- `FileThumbnailImage.swift` (48): thumbnail preview.
- `QuickDropPanel.swift` (~300) / `QuickDropView.swift` (~450): the popup (6 wells), option list (Up/Down/Return/Esc via the panel), run list, preference keys.

## Engines (`Sources/Nimbus/Engines/`)

Native Swift ports of the old Node tools; no UI (video shells out to the bundled ffmpeg). Each is `static func run(input:...) async throws -> URL`, writing `name.ext` (then `name-2.ext`) into `~/Nimbus`, never beside the original.

- `EngineSupport.swift`: `CompressionLevel` (low/high/lossless), `EngineError`, `EngineIO` (size limits, content sniffing via ImageIO, decode/encode, unique output name).
- `WebPCodec.swift`: libwebp encoder wrapper.
- `ImageCompressor.swift`, `ImageConverter.swift`, `ImageTrimmer.swift`, `FaviconMaker.swift` (zip of favicons), `VideoConverter.swift` (MP4/MOV via AVAssetExportSession H.264, WebM delegates to VideoCompressor), `VideoCompressor.swift` (always WebM: VP9 + Opus through the bundled LGPL ffmpeg run as a `Process`; binary at `Resources/ffmpeg`, rebuilt by `Tools/build-ffmpeg.sh`).
- `EnginesSelfCheck.swift`: `enginesSelfCheck()`, run from a scratch harness.

## Docs and memory

- `docs/tool-inputs.md`: the six tools and their options.
- Rules and lessons: auto memory, `~/.claude/projects/-Users-carlos-Projetos-Treendz-nimbus-swift/memory/` (see CLAUDE.md).
- `docs/memory/archive/`: old workboard / feature-spec snapshots. Do not read routinely.

## Adding a tool (checklist)

1. `ToolCatalog.swift` entry (it appears as a Quick Drop well automatically).
2. Acceptance/multi-file rules in `QuickDropView.swift` if not image/multi.
3. Engine under `Engines/`, wired in `EngineToolRunner`; options in `NimbusTool.choices`.
4. New `.swift` file: register in `project.pbxproj`.
5. Name, summary and any new strings: add en + pt-BR to `Localizable.xcstrings`.
