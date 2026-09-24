# File map

Where things live, so you can open the right file instead of rereading the
tree. Line counts are approximate (2026-09-18). Update this file when you add,
rename or split a file.

## Entry points and build

- `Package.swift`: SwiftPM target `Nimbus` (macOS 14, Swift tools 6.0), depends on Sparkle.
- `Nimbus.xcodeproj/project.pbxproj`: Xcode build. A new `.swift` file needs both pbxproj entries (see auto memory `sidecar-tools.md`).
- `Makefile`: `make build`, `make lint`, `make ci`.
- `.github/workflows/ci.yml`: CI build, versioned release, Homebrew cask.
- `Sources/Nimbus/Info.plist`, `Nimbus.entitlements`, `Resources/` (AppIcon.icns, TrayIcon.png).

## App shell (`Sources/Nimbus/`)

- `NimbusApp.swift` (584): `@main NimbusApp`, `AppDelegate` (status item, menu, main window, global hotkeys, launch wiring).
- `MainWindowOpener.swift` (38): opens/reuses the single main window.
- `ToolLauncher.swift` (35): single path to open a tool (`ToolOpenRequest`, `ToolOpenSource`, pending/consume). `AppDelegate.open(_:)` shows/centers the window.
- `FirstFieldFocus.swift` (75): `.background` anchor that focuses the first editable text field of the detail pane.
- `MainWindowView.swift` (204): `NavigationSplitView`, `SidebarSearchField`, `ToolDetailView` (routes File / Form / Native), `GenericToolView` fallback.
- `GlassBackground.swift` (90): Liquid Glass on macOS 26, vibrancy fallback.
- `PreferencesView.swift` (288): tabs General, API Keys, Quick Drop, Account.
- `UpdateChecker.swift` (80): Sparkle `AppUpdater`, `UpdateIndicator` badge.
- `LaunchAtLogin.swift` (37): `SMAppService` toggle.
- `GlobalHotKey.swift` (145): `QuickDropShortcut`, `SpotlightShortcut`, `PickColorShortcut`, Carbon hotkey wrapper.

## Extensions (`Extensions/`, outside `Sources/Nimbus`, Xcode-only)

- `Extensions/FinderAction/`: Finder Quick Action app extension (`com.apple.services`, sandboxed, own entitlements). Routes image/movie/font to `nimbus://open?tool=…&file=…`. See memory `pbxproj-new-target`.

## Tool catalog and routing

- `ToolCatalog.swift` (79): `ToolGroup`, `NimbusTool`, `ToolCatalog` (source of truth for which tools exist and are visible), `NimbusTheme`.
- `FileToolView.swift` (1032): `FileToolKind`, `FileToolConfiguration`, `CompressionPreset`, file tool UI, completion panel, palette swatches.
- `FileAcceptance.swift` (77): accepted `UTType`s per input kind.
- `FileThumbnailImage.swift` (48): thumbnail preview.
- `FormToolConfiguration.swift` (94): `FormSlice`, `FormToolKind`, `FormToolConfiguration`.
- `FormToolView.swift` (254): form tool shell (header, fields, submit, result).
- `FormFieldsSliceA.swift` (430) / `FormFieldsSliceB.swift` (472): per-tool fields and `canSubmit`.
- `FormResultView.swift` (107): `FormRunResult`, result dispatcher.
- `FormResultSliceA.swift` (438): WHOIS, DNS, Site Speed, WordPress result models and views.
- `FormResultSliceB.swift` (319): Copy Generator, Font Clamp, minify, password, color convert, contrast results.
- `FormControls.swift` (521): `FormRow`, `FormSectionHeader`, `FormTextEditor`, `CompactFileField`, `DynamicList`, `CopyButton`, `KeyValueTable`, `BadgeView`.
- `NativeToolView.swift` (160): `NativeToolKind`, `PickColorView` (tools that run in Swift, no sidecar).
- `Eyedropper.swift` (493): custom live eyedropper (ScreenCaptureKit). Currently hidden; system `NSColorSampler` is used.

## Quick Drop and Spotlight

- `QuickDropPanel.swift` (195) / `QuickDropView.swift` (443): drop panel, run list, preferences keys.
- `SpotlightPanel.swift` (165) / `SpotlightView.swift` (110): tool search panel.

## Backend, auth, quota

- `NimbusAPI.swift` (306): `NimbusEndpoint`, `NimbusConfiguration`, token providers, `KeychainSecretStore`, `NimbusAPIClient` (form + multipart).
- `SidecarProcess.swift` (222): launches the local Node sidecar.
- `SupabaseConfiguration.swift` (22): URL, anon key, callback.
- `SupabaseAuthClient.swift` (172): PKCE, GoTrue exchange/refresh/user.
- `LoopbackAuthServer.swift` (237): POSIX-socket loopback for the OAuth callback (not NWListener).
- `AuthSession.swift` (129): `AuthState`, session restore/refresh.
- `AuthGateView.swift` (125) / `ProviderBrandMark.swift` (212): login gate and provider logos.
- `UsageQuota.swift` (268): per-plan daily limits, trial, `UsageIndicator`.

## Sidecar (`Sidecar/`, Node)

- `server.mjs`, `router.mjs`: HTTP server and route table.
- `tools/<tool>.mjs`: one file per tool (ported from the web app). Adding a tool: see auto memory `sidecar-tools.md`.
- `extractPaletteKMeans.mjs`, `pdfNodeSetup.mjs`, `configurePdfParseWorker.mjs`, `assets/`.

## Docs and memory

- `docs/tool-inputs.md`: input fields per tool (spec for forms).
- Rules and lessons: auto memory, `~/.claude/projects/-Users-carlos-Projetos-Treendz-nimbus-swift/memory/` (see CLAUDE.md).
- `docs/memory/archive/`: old workboard / feature-spec snapshots. Do not read routinely.

## Adding a tool (checklist)

1. `ToolCatalog.swift` entry.
2. `FileToolKind`+`FileToolConfiguration`, or `FormToolKind`+fields in a `FormFieldsSlice*` + result in a `FormResultSlice*`, or `NativeToolKind`.
3. `Sidecar/tools/<id>.mjs` + route (unless native).
4. `docs/tool-inputs.md` section.
5. New `.swift` file: register in `project.pbxproj`.
