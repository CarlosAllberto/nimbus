# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project memory

Durable lessons live in `docs/memory/lessons.md` (append-only Problem/Cause/Rule/Context
log) and `docs/memory/rules.md` (the current, canonical rules promoted from
lessons). Check `rules.md` before making non-obvious decisions; add an entry
to `lessons.md` after fixing a bug or hitting a gotcha worth remembering.

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
policy) with a single SwiftUI window shell, all under `Sources/Nimbus/`
(flat, no submodules):

- **`NimbusApp.swift`** — `@main` entry point. `AppDelegate`
  (`NSApplicationDelegate`) owns the `NSStatusItem`/menu and manages the one
  `NSWindow` imperatively (creating it lazily off the SwiftUI `WindowGroup`,
  re-showing/re-activating it on dock/menu-bar clicks). SwiftUI only supplies
  the window's content view via `MainWindowView`.
- **`ToolCatalog.swift`** — static catalog of `NimbusTool` entries (id, name,
  summary, icon, `ToolGroup`). This is the single source of truth for what
  tools exist and which sidebar group (`web`, `studio`, `code`, `tools`) they
  belong to. Adding a tool starts here.
- **`MainWindowView.swift`** — `NavigationSplitView` shell: sidebar lists/filters
  tools from `ToolCatalog` grouped by `ToolGroup`; the detail pane tries
  `FileToolConfiguration.configuration(for:)` first, then
  `FormToolConfiguration.configuration(for:)`, and falls back to the
  `GenericToolView` placeholder. Every tool in the catalog currently resolves to
  one of the first two, so the placeholder should not be reachable.
- **`FileToolView.swift`** — the file-based tool UI (drag/drop or file picker,
  per-tool option controls, action button). `FileToolKind` is a second,
  narrower enum of tool ids whose primary input is a file;
  `FileToolConfiguration.configuration(for:)` maps a tool id to its
  `FileAcceptance`, whether multiple files are allowed, and per-kind default
  output format/dimension.
- **`FormToolView.swift`** — the field-based tool UI for tools with no primary
  file: header, scrolling field area, action button. `FormToolKind` enumerates
  those tool ids and `FormToolConfiguration` carries the action title;
  `FormToolKind.slice` routes each kind to `FormFieldsSliceA` or
  `FormFieldsSliceB`, which own the actual fields and the `canSubmit` rule per
  tool. Shared building blocks (`FormRow`, `FormSectionHeader`,
  `CompactFileField`, `DynamicList`) live in `FormControls.swift`.
- **`FileAcceptance.swift`** — the accepted-input type (image/video/font/document)
  with its allowed `UTType`s, shared by the drop zone in `FileToolView` and the
  `CompactFileField` used inside forms.
- The three catalogs are intentionally decoupled: a new tool needs an entry in
  `ToolCatalog` plus either `FileToolKind`/`FileToolConfiguration` or
  `FormToolKind`/`FormToolConfiguration`. The per-tool input fields are specified
  in `docs/tool-inputs.md`.
- **`NimbusAPI.swift`** — networking/auth layer, currently not wired into the
  UI (the action button is a no-op in both `FileToolView` and `FormToolView`;
  validation only enables or disables it). `NimbusEndpoint.path(for:)`
  maps a `NimbusTool` to a backend route under
  `/api/tools/{group}/{segment}`, where `segment` is the tool id unless
  overridden in the `aliases` table (e.g. `whois-scan` → `whois`).
  `NimbusAPIClient` posts multipart file uploads to `NimbusConfiguration.production`
  (`https://www.nimbushelp.com`) and attaches a bearer token from a
  `NimbusTokenProvider`; `KeychainTokenStore` reads/writes that token to the
  macOS Keychain under service `com.treendz.nimbus` / account
  `supabase-access-token`. `EmptyTokenProvider` is the default (no auth).
- **`PreferencesView.swift`** — appearance (system/light/dark) picker, backed
  by `NimbusTheme` (defined in `ToolCatalog.swift`).
