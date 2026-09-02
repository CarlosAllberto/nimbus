# Lessons

Append-only log of notable problems, bugs, and decisions encountered while
working on this codebase. Newest entries first. When a lesson yields a durable
rule, promote it to [rules.md](rules.md).

## Format

### YYYY-MM-DD — short title

- **Problem:** what was observed (error, crash, wrong behavior, bad decision).
- **Cause:** root cause.
- **Rule:** the actionable takeaway (also promoted to rules.md if durable).
- **Context:** links, files, or commits relevant to this entry.

## Entries

### 2026-08-31 — SwiftUI `.shadow` over a glass backdrop paints a square halo

- **Problem:** the Quick Drop card had a dark square halo around its rounded
  corners. Adding a transparent margin only made the square bigger, and
  `.clipShape` plus `.compositingGroup()` only made it fainter.
- **Cause:** `.shadow` derives its silhouette from the alpha of what it
  shadows. A `glassEffect` backdrop (same for an `NSVisualEffectView` through
  `NSViewRepresentable`) is composited outside the SwiftUI layer, so there is
  no alpha to read and the modifier falls back to the bounding box.
- **Rule:** a panel whose background is glass or vibrancy gets its shadow from
  the window (`hasShadow = true`, plus `invalidateShadow()` after the content is
  on screen), not from `.shadow`. The tradeoff is that the window shadow does
  not animate with an entrance transform.
- **Context:** `Sources/Nimbus/QuickDropView.swift`, `QuickDropPanel.swift`.
  Diagnosed by temporarily colouring the shadow red — the halo turned red,
  which settled in one build what several guesses had not.

### 2026-08-31 — `GlassEffectContainer` renders across its whole rect

- **Problem:** the glass background painted a square region behind the rounded
  card even with the corner radius passed to `glassEffect(_:in:)`.
- **Cause:** `GlassEffectContainer` exists so several glass elements can share
  one backdrop; wrapping a single element made it render across the container.
- **Rule:** with one glass element, apply `.glassEffect(_:in:)` directly and
  skip the container.
- **Context:** `Sources/Nimbus/GlassBackground.swift`.

### 2026-08-31 — A `.titled` panel sits lower than its requested margin

- **Problem:** the Quick Drop panel appeared far below the intended top inset,
  with a small empty strip above the card.
- **Cause:** `styleMask: [.titled, …]` reserves a titlebar, so the window frame
  was taller than the card and `setFrameOrigin` positioned the frame, not the
  visible content.
- **Rule:** a HUD panel is `.borderless` (with `canBecomeKey` overridden so it
  still takes focus); reserve `.titled` for windows that actually show a
  titlebar.
- **Context:** `Sources/Nimbus/QuickDropPanel.swift`.

### 2026-08-31 — `if #available` does not gate symbol resolution

- **Problem:** the Quick Drop panel uses Liquid Glass (`glassEffect`,
  `GlassEffectContainer`), which exists only in the macOS 26 SDK. Guarding it with
  `if #available(macOS 26, *)` would still have failed to compile on CI, which
  runs `macos-14`.
- **Cause:** availability is a *runtime* check; the symbol must still resolve at
  *compile* time, against whatever SDK the toolchain has.
- **Rule:** a symbol from an SDK newer than the oldest toolchain that must build
  the project needs a compiler gate — `#if compiler(>=6.2)` — with the fallback
  outside it. Keep the newer-SDK code in its own `@available` type so the `#if`
  region stays small.
- **Context:** `Sources/Nimbus/GlassBackground.swift`; `.github/workflows/ci.yml`
  runs on `macos-14`.

### 2026-08-31 — A file importer sheet resigns its panel's key status

- **Problem:** the Quick Drop panel closes on `windowDidResignKey`. Clicking a
  well opens `.fileImporter`, which destroyed the panel under the open dialog.
- **Cause:** `.fileImporter` presents `NSOpenPanel` as a window-modal sheet, and
  attaching a sheet makes the parent window resign key.
- **Rule:** a panel that dismisses on resign-key needs a suppression counter
  (an `Int`, not a `Bool` — several wells can each present one) checked in the
  single method every dismissal path routes through. Guarding only one caller
  leaves the other paths free to reintroduce the bug.
- **Context:** `QuickDropSession.importerDepth`, checked in
  `QuickDropPanelController.close(restoringPreviousApp:)`.

### 2026-08-31 — Activating a panel is not the same as changing activation policy

- **Problem:** it looked as though showing Quick Drop would need `.regular` to
  take keyboard focus and show an open panel.
- **Cause:** conflating activation with activation *policy*. An `.accessory` app
  can activate, become key, take keystrokes and present `NSOpenPanel`; it simply
  has no Dock tile. Flipping to `.regular` would flash a Dock icon on every
  invocation.
- **Rule:** transient HUD panels activate the app but never touch
  `setActivationPolicy`; only a real window does. And `applicationDidBecomeActive`
  must not raise the main window while such a panel is up.
- **Context:** `Sources/Nimbus/QuickDropPanel.swift`, `NimbusApp.swift`.

### 2026-08-31 — `.frame(width:)` centers a control that hugs its content

- **Problem:** the segmented Strategy picker and the menu pickers in the form
  tools rendered indented from the left, not flush with the text fields above.
- **Cause:** `.frame(width:)` centers by default, and a menu or segmented picker
  sizes to its content rather than filling the frame, so the leftover width
  showed up as a leading gap. Text fields hid the bug because they fill.
- **Rule:** a fixed-width control in a leading-aligned form uses
  `.frame(width:, alignment: .leading)`.
- **Context:** `menuPicker` in both `FormFieldsSlice*.swift`, site-speed Strategy.

### 2026-08-31 — ScrollView clips field borders and focus rings

- **Problem:** in `FormToolView`, a focused text field lost its ring on the left
  edge and the last field of the Contract PDF form was cut off at the bottom.
- **Cause:** a `ScrollView` clips to its bounds, and a field draws its border and
  focus ring slightly outside its own frame. With the content flush to the scroll
  bounds there was nothing to draw into.
- **Rule:** content inside a `ScrollView` gets a small inset on all sides
  (`focusRingInset` in `FormToolView`); compensate it in the container's own
  padding so the columns stay aligned with the header.
- **Context:** `Sources/Nimbus/FormToolView.swift`.

### 2026-08-31 — Type-check timeout on a form view with many `.onChange` modifiers

- **Problem:** `swift build` failed with "unable to type-check this expression in
  reasonable time" on the Contract PDF form, a single view with 16 text fields.
- **Cause:** the 16 `.onChange` modifiers chained onto one view body, not the
  field count itself. Splitting the fields into sub-views without also splitting
  the `.onChange` chain still timed out.
- **Rule:** when a form grows past a handful of fields, group the fields *and*
  their `.onChange` modifiers into per-section `Group`s, so no single expression
  carries the whole validation chain.
- **Context:** `Sources/Nimbus/FormFieldsSliceA.swift`, `contractPDFFields`.

### 2026-08-31 — `ForEach(items.indices)` breaks row bindings on removal

- **Problem:** the dynamic row list used by JSON Creator and Copy Generator was
  first written as `ForEach(items.indices, id: \.self)` with `remove(at:)`.
- **Cause:** index-based identity: removing a middle row shifts every later
  index, so the surviving rows' `Binding`s point at the wrong elements (and an
  in-flight index can go out of range).
- **Rule:** dynamic lists take `Item: Identifiable`, iterate `ForEach($items)`
  for direct bindings, and remove by `id` — never by index.
- **Context:** `DynamicList` in `Sources/Nimbus/FormControls.swift`.

### 2026-08-31 — A new source file must be registered in project.pbxproj by hand

- **Problem:** files added for the form-input work built fine under SwiftPM but
  would not have compiled in the Xcode target.
- **Cause:** `Nimbus.xcodeproj` does not use synchronized groups, so a new
  file needs its own `PBXBuildFile`, `PBXFileReference`, group membership, and
  Sources build-phase entry.
- **Rule:** adding a source file means editing `project.pbxproj` too; verify with
  `plutil -lint Nimbus.xcodeproj/project.pbxproj`. Keeping the two build
  entry points compatible is a standing constraint (see CLAUDE.md).
- **Context:** `Nimbus.xcodeproj/project.pbxproj`.

### 2026-09-01 — `Package.swift` never needed the new-file edit

- **Problem:** the standing rule said a new Swift file must be registered in both
  `Package.swift` and `project.pbxproj`. Half of it was busywork.
- **Cause:** the rule was written from the Xcode symptom (a file that builds under
  SwiftPM but not in the Xcode target) without checking the manifest. The target
  is `.executableTarget(name: "Nimbus", path: "Sources/Nimbus", exclude: ["Info.plist"])`
  — `path:` with no explicit `sources:`, so SwiftPM globs the directory.
- **Rule:** only `project.pbxproj` needs the manual registration; leave
  `Package.swift` alone unless the target ever gains an explicit `sources:` list.
- **Context:** `Package.swift`, verified while reviewing the form-tool contract.

### 2026-09-01 — `NSImage(data:)` decodes SVG, so an SVG result previews for free

- **Problem:** QR Code was fixed to SVG output, and the generic result panel
  previews a result only when it is an image — an SVG looked like it would fall
  back to a generic document icon.
- **Cause:** assumption. macOS actually decodes SVG: `NSImage(data:)` returns an
  image backed by `_NSSVGImageRep`, and `UTType(mimeType: "image/svg+xml")`
  resolves to `public.svg-image`, which conforms to `.image` and yields
  `preferredFilenameExtension` `"svg"`.
- **Rule:** an SVG body needs no special case in the result panel — the
  `conforms(to: .image)` branch handles it, and the suggested filename gets its
  extension from `UTType` on its own. Keep the preview's white backing, or a
  black-on-transparent QR disappears.
- **Context:** `FormResultView.interpretResult`, `Sidecar/tools/qrcode.mjs`.

### 2026-09-01 — A ported error message is UI text; ported generated content is not

- **Problem:** the Next routes answer in Portuguese and the Nimbus UI is English,
  so ported error strings would surface Portuguese inside an English interface.
  Applying that translation bluntly would also have rewritten Policy Generator's
  privacy-policy and terms templates.
- **Cause:** "port the route verbatim" and "the UI is in English" collide, and
  the line between them is not the file — it is what the string *is*.
- **Rule:** translate error messages to English; never translate the content a
  tool exists to generate. Policy Generator's document stays PT-BR (a user
  decision, 2026-09-01): translating it would stop being a port and become new
  legal text needing review.
- **Context:** `Sidecar/tools/policy-generator.mjs` and the other 12 ported routes.

### 2026-09-01 — A slice's foundation must land before another slice's signature depends on it

- **Problem:** the contract let both implementers write their form slices in
  parallel. `FormFieldsSliceA`/`B` were gaining `@Binding var fields`/`files`,
  and `FormToolView` (a third file, in the foundation slice) was gaining the call
  that passes them — so whichever landed first left the tree uncompilable.
- **Cause:** file ownership was clean, but a *signature* spans the caller and the
  callee, which lived in different owners' files.
- **Rule:** when a slice changes a type's signature, the foundation slice adds the
  new members to every declaration up front (even empty), and dependent slices
  start on work with no Swift dependency — here, the sidecar `.mjs` ports — until
  the foundation is signalled as landed on the workboard.
- **Context:** Slice 0 vs. Slice B of the form-tool feature.

### 2026-09-01 — A view file existing is not the same as it being reachable

- **Problem:** `PreferencesView.swift` held the Gemini/PageSpeed `SecureField`s
  needed to test the 3 key-gated tools, but nothing in the app ever presented
  it — no menu item, no window, no theme binding wired anywhere. `grep -rl
  PreferencesView Sources/` turned up only the file itself.
- **Cause:** the feature-spec for the Keychain/Preferences work specified the
  view's body verbatim but never assigned a slice to wire it into
  `NimbusApp.swift`/the status-item menu, and no reviewer noticed because
  `swift build` succeeds fine on an unreferenced top-level `struct`.
- **Rule:** when a contract adds or rewrites a `View` meant to be user-facing
  (not a subview composed by an existing caller), the ownership table must
  include the call site that presents it, and the Warden's live-verification
  pass must include actually opening it, not just reading the diff.
- **Context:** wired via `Settings` scene (`NimbusApp.swift`) + a "Preferences…"
  item in the status-item `NSMenu`, using `@AppStorage` for `NimbusTheme`
  persistence (its `RawRepresentable` conformance made this a 1-line
  `@AppStorage` property instead of manual `UserDefaults` plumbing).

### 2026-09-02 — A bare SwiftPM executable cannot handle a custom URL scheme

- **Problem:** Google OAuth appeared to "open a second Nimbus" and leave the
  browser spinning forever. Three rounds of window-management fixes in
  `AppDelegate` (focus guards, `WindowGroup` → `Window(id:)`, an `openWindow`
  bridge) changed nothing, because none of them addressed the real cause.
- **Cause:** Xcode was running the `Package.swift` target, which produces a bare
  Mach-O executable with no `.app` bundle and therefore no Info.plist that
  LaunchServices can register for `nimbus:`. When the browser handed back
  `nimbus://auth-callback?code=…`, macOS resolved the scheme to the *other*
  build — the `.app` from `Nimbus.xcodeproj` — and launched it as a **second
  process**. That process showed its own main window ("the other Nimbus") and
  discarded the code, because `pendingCodeVerifier` lives in the memory of the
  process that started the sign-in. Both symptoms, one cause.
- **Rule:** anything that depends on bundle identity — URL schemes, Launch
  Services, Info.plist keys, notifications — only works in the `.xcodeproj`
  build. `swift build`/the SwiftPM scheme is for compiling, not for running
  those features. When a bundle-dependent feature "doesn't work", check *which
  binary is actually running* (`ps -eo comm= | grep Nimbus`) before touching code.
- **Context:** the original feature-spec did note that `swift build` produces no
  `.app`; the note existed but nobody checked it against the running process.
  Diagnosed by logging process paths during a real reproduction, after three
  code-level hypotheses had failed.

### 2026-09-02 — SwiftUI opens a duplicate window on external open events

- **Problem:** delivering `nimbus://auth-callback` to the correctly-bundled
  `.app` still produced a second main window, on top of the existing one.
- **Cause:** the scene answers the system "open URL" event by building another
  instance of itself, *before* `application(_:open:)` runs. Instrumented log:
  `MainWindowView.onAppear` fired a second time and `NSApp.windows` went 2 → 3
  (a new `TUINSWindow`). Switching `WindowGroup` → `Window(id:)` does not stop
  this — a `Window` still responds to external events.
- **Rule:** when an `AppDelegate` fully handles URL/user-activity events, mark
  the scene `.handlesExternalEvents(matching: [])` so SwiftUI does not open a
  window of its own for the same event. No focus guard in `AppDelegate` can fix
  this, because the extra window is created outside your code.
- **Context:** also found on the reopen path that SwiftUI re-applies its
  `.windowStyle` *after* the AppKit chrome is set, resetting
  `titlebarAppearsTransparent`; the chrome is now re-applied one run-loop tick
  later (`applyChrome(to:)`).

### 2026-09-02 — Verify GUI behaviour by instrumenting and running, not by reading

- **Problem:** three consecutive fixes were shipped on plausible-sounding
  hypotheses, each verified only by `swift build` + `xcodebuild` succeeding.
  All three left the bug untouched, and each round cost a full user test cycle.
- **Cause:** no agent in this setup can click a GUI, so "verification" silently
  degraded to "it compiles" — which cannot distinguish a correct fix from an
  irrelevant one.
- **Rule:** for a runtime/GUI bug, add temporary logging to a file, run the real
  binary, drive it from the shell (`open "nimbus://…"`, and temporary debug URL
  hooks for actions that need a click), and diff the measurements before and
  after. Only then hand it to the user. A green build is not evidence about
  runtime behaviour.
- **Context:** the instrumented run identified both root causes in a single pass
  after three blind rounds.

### 2026-09-02 — NWListener fails with EINVAL here; an error message that guesses hides it

- **Problem:** the loopback OAuth server reported "port already in use" while the
  port was demonstrably free (`lsof` twice, plus a plain POSIX `bind` on the very
  same port succeeding).
- **Cause:** two compounding faults. `NWListener` fails to start with `EINVAL`
  for *every* port in this app on this macOS — measured in-app: auto-assigned,
  8123 and 53682 all failed, while a POSIX socket bound fine in the same
  process. And `start()` mapped every listener failure to `.portUnavailable`,
  whose message asserted a port conflict, so the one diagnostic the user could
  see pointed away from the real cause.
- **Rule:** an error case may only claim what it actually knows. Carry the real
  reason (`strerror(errno)`, the underlying error) instead of naming the most
  likely cause, or the message becomes a false lead — this one cost a full
  debugging round. For a loopback listener, a POSIX socket plus `DispatchSource`
  is the dependable transport here; keep `NWListener` out of this path.
- **Context:** `LoopbackAuthServer` now binds a POSIX socket, and its error is
  `.listenerFailed(String)` carrying `strerror`. Same public API, so
  `AuthSession` was untouched. Verified in the running app: bind, browser gets
  the completion page, code extracted, port released, and three immediate
  rebinds after `stop()`.

### 2026-09-02 — A new Swift file needs both pbxproj entries, or only Xcode breaks

- **Problem:** twice in one feature the user's build failed with `cannot find
  type 'X' in scope` for a file that plainly existed and that `swift build`
  compiled without complaint.
- **Cause:** SwiftPM globs the source folder, so a new file is picked up the
  moment it is written. The Xcode target reads `project.pbxproj`, where a file
  needs *two* linked entries — a `PBXFileReference` and a `PBXBuildFile` naming
  it as `fileRef` — plus membership in the group and the Sources phase. Once the
  pair was half-written (a file reference and a Sources entry, no build file),
  and once the file was never registered at all. `plutil -lint` passes either
  way: it validates plist syntax, not the build graph.
- **Rule:** adding a `.swift` file is not done until the pbxproj pair exists, and
  the only proof is `xcodebuild -project Nimbus.xcodeproj -scheme Nimbus
  -configuration Debug -destination 'platform=macOS' build`. Treat a green
  `swift build` on a change that adds files as saying nothing about Xcode.
- **Context:** `AuthSession.swift`, then `LoopbackAuthServer.swift`. Both
  surfaced as a broken build in the user's hands rather than in ours.

### 2026-09-02 — A fix verified in the wrong environment is not verified

- **Problem:** the blurred titlebar was reported fixed, then came back. The fix
  passed every check available locally — launching the built `.app` directly
  showed a crisp title — and still failed for the user every time.
- **Cause:** the fix re-applied the window chrome one run-loop tick after SwiftUI
  reset it. Instrumented, the reset lands at ~0.2s and the correction at ~0.5s:
  correct, but a race. The user runs from Xcode with a debugger attached, which
  reorders the two, and the direct launch used for verification never could.
- **Rule:** when a fix depends on ordering, reproduce in the environment the
  report came from, or remove the ordering. Reasserting an invariant — here KVO
  on `titlebarAppearsTransparent`, putting it back whoever clears it — is
  order-independent and needs no timing assumption to hold.
- **Context:** three rounds were spent on "works here" before the difference in
  how the app was launched turned out to be the whole story.

### 2026-09-02 — Two `.fileImporter`s in one hierarchy: the nested one never opens

- **Problem:** clicking the background-image field in Device Wrapper did
  nothing, while dropping a file onto the same field worked.
- **Cause:** `FileToolView` already carries a `.fileImporter` for its main drop
  zone, and `CompactFileField` brought a second one nested inside it. Drops need
  no presentation, which is why only the click was dead. The same component had
  always worked in forms, and `FormToolView` has no importer of its own — the
  asymmetry was the tell.
- **Rule:** treat `.fileImporter` (and sheet-style presentations generally) as
  something a view hierarchy gets one of. A reusable field that opens a file
  panel should drive `NSOpenPanel` itself rather than compete for the
  presentation, which also frees it to work anywhere it is dropped in.
- **Context:** `CompactFileField` now opens `NSOpenPanel` directly, activating
  the app first the way `QuickDropWell` already did.

### 2026-09-02 — Layout that works by accident breaks the moment it is copied

- **Problem:** with the sidebar hidden, form tools drew their title underneath
  the sidebar toggle button. File tools, with the identical 52pt leading inset
  for the same case, were fine.
- **Cause:** the inset was never what cleared the button. A `.frame(maxWidth:)`
  narrower than the pane gets centred, and that offset is what carried the
  header across. File tools cap at 460pt and gain enough offset; forms capped at
  560pt and gained too little. Both were measured receiving
  `isSidebarVisible == false` and applying the same 76pt — the constant was
  innocent.
- **Rule:** when two screens share a constant and only one looks right, the
  constant is not doing the work. Find what actually positions the content
  before adjusting the number, or the fix lands on the wrong mechanism.
- **Context:** forms now use the same 460pt as file tools, which fixed the
  overlap and the too-wide content in one change. The alignment still rests on
  centring, so a resizable or narrow window would bring it back for both.

### 2026-09-02 — The same Xcode error, two different causes

- **Problem:** `cannot find 'LoopbackAuthServer' in scope` in Xcode, for a file
  that existed and was committed. Earlier in the same session an identical
  message meant the pbxproj was genuinely missing entries, so the reflex was to
  go fix the pbxproj again.
- **Cause:** this time the project on disk was complete — a clean `xcodebuild`
  with DerivedData removed succeeded. `project.pbxproj` had been rewritten
  several times while the user's Xcode had the project open, and Xcode kept
  serving its stale in-memory model, which did not know the file.
- **Rule:** the message does not name the cause. Build from the command line
  with DerivedData cleared first: if that succeeds, the project is fine and the
  answer is to quit Xcode fully (⌘Q, not just the window), reopen, and Clean
  Build Folder — editing the pbxproj again would be fixing something that is not
  broken. If it fails, the registration really is missing.
- **Context:** worth checking every file at once rather than the one in the
  message, because a pbxproj entry can also be present but left out of the group
  or the Sources phase — the pair existing is not the same as the file being
  built.

### 2026-09-02 — A contract can omit the fact a decision needs

- **Problem:** the usage gate could refund a unit the user never spent. The
  quota check fails open — no session, no token, request failed — and lets the
  run through without consuming anything. If the local run then failed, the
  release fired anyway, decrementing a real count and handing out credit.
- **Cause:** `GateResult` was `.allowed | .blocked`, so the call site could not
  tell "allowed because it consumed" from "allowed because the check failed
  open". Neither implementer could have caught it: each built exactly what the
  contract described, and the missing piece was in the type the contract
  defined, not in the code written against it. The Warden found it by reading
  the fail-open paths against the release call sites.
- **Rule:** when a contract defines a result type, check that it carries
  everything its consumers must decide with — especially where one branch is a
  fallback that did less work than it appears. `.allowed(consumed: Bool)` costs
  nothing and makes the wrong call impossible to write.
- **Context:** the sibling finding — whether releasing hurts a Pro account —
  was answered by reading the function in the database: it floors at zero and
  filters to free/basic, so it is a no-op there. Both were reported as findings
  rather than assumptions, which is what made them cheap to settle.
