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
policy) with a single SwiftUI window shell, all under `Sources/Nimbus/`
(flat, no submodules). `docs/memory/memory.md` lists every file.

- **`NimbusApp.swift`** — `@main` entry point with one `Window(id: "main")`
  scene marked `.handlesExternalEvents(matching: [])`. `AppDelegate` owns the
  status item/menu, global hotkeys, and the main `NSWindow` imperatively
  (adopting the scene's window, or hosting `MainWindowView` itself when a
  cold launch from a URL gives the scene no window). It also handles
  `nimbus://open?tool=<id>&file=<path>` deep links and Core Spotlight
  activities.
- **`ToolLauncher.swift`** — the single path that opens a tool. Quick search,
  deep links, Spotlight and the Finder action all send a `ToolOpenRequest`;
  deep-link input is validated there (tool exists, files are absolute,
  regular and accepted). Opening never runs a tool.
- **`ToolCatalog.swift`** — static catalog of `NimbusTool` entries (id, name,
  summary, icon, `ToolGroup`). Single source of truth for which tools exist
  and their sidebar group (`web`, `studio`, `code`, `tools`). Adding a tool
  starts here.
- **`MainWindowView.swift`** — `NavigationSplitView` shell. The detail pane
  tries `FileToolConfiguration`, then `FormToolConfiguration`, then
  `NativeToolKind`, falling back to `GenericToolView` (should be unreachable).
  `FirstFieldFocus` focuses the first text field of form tools on open.
- **`FileToolView.swift`** — file-first tools (drop zone/picker, options,
  action). `FileToolKind` + `FileToolConfiguration` give each tool its
  `FileAcceptance`, `allowsMultipleFiles` and defaults. Files are processed
  one at a time; results are written beside the source.
- **`FormToolView.swift`** — field-based tools. `FormToolKind` (in
  `FormToolConfiguration.swift`) routes each kind to `FormFieldsSliceA`/`B`
  (fields, `canSubmit`) and `FormResultSliceA`/`B` (result views), and
  declares steps and `fillsHeight(atStep:)`. Shared building blocks
  (`FormRow`, `FormTextEditor`, `CompactFileField`, `DynamicList`,
  `CopyButton`, `CopyResultCard`, `CodeBlockView`) live in `FormControls.swift`.
- **`NativeToolView.swift`** — tools that run in Swift with no sidecar
  (Pick Color).
- The catalogs are intentionally decoupled: a new tool needs an entry in
  `ToolCatalog` plus one of the kind/configuration enums. Per-tool input
  fields are specified in `docs/tool-inputs.md`.
- **`Sidecar/`** — a local Node server (`server.mjs`, one `tools/<id>.mjs`
  per tool, ported from the Next app) launched by `SidecarProcess.swift`.
  Tool logic lives here, not in Swift.
- **`NimbusAPI.swift`** — `NimbusAPIClient` posts multipart requests
  (`process` for file tools, `processForm` for forms) to the sidecar, authed
  with `SidecarTokenProvider`. `NimbusEndpoint.path(for:)` maps a tool to
  `/api/tools/{group}/{segment}` (`aliases` overrides, e.g. `whois-scan` →
  `whois`). `KeychainSecretStore`/`KeychainTokenStore` keep secrets in the
  Keychain under service `com.treendz.nimbus`.
- **Auth and quota** — Supabase OAuth with PKCE (`SupabaseAuthClient`,
  `LoopbackAuthServer` on a POSIX socket, `AuthSession`, `AuthGateView`).
  `UsageQuota` meters tool runs per plan; every call site that runs a tool
  must gate through it.
- **Panels** — Quick search (`SpotlightPanel`/`SpotlightView`) and Quick Drop
  (`QuickDropPanel`/`QuickDropView`) are non-activating HUD panels forced to
  dark appearance over `GlassBackground(.prominent)`.
- **`Extensions/FinderAction/`** — Finder quick action (Action Extension
  target, Xcode only, sandboxed). Routes images/videos/fonts to their tool
  via a `nimbus://` link. Loads only in signed builds; CI builds unsigned.
- **`PreferencesView.swift`** — General, API Keys, Quick Drop and Account
  tabs; theme is `NimbusTheme` (in `ToolCatalog.swift`), applied inside
  `MainWindowView`.
