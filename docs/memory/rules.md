# Rules

Canonical, current rules for working in this codebase — the distilled,
actionable takeaways promoted from [lessons.md](lessons.md). Keep this list
short and up to date; if a rule stops applying, remove it instead of letting
it go stale.

## Format

- **Rule:** the takeaway, stated so it's actionable.
- **Why:** the reason (link back to the lessons.md entry that motivated it).

## Current rules

- **Rule:** tool logic is not reimplemented in Swift. It is ported from the
  matching `app/api/tools/{group}/{segment}/route.ts` in the Next repo into
  `Sidecar/tools/<id>.mjs`, minus session, Supabase and quota. Keep the request
  fields, the status codes and the pipeline settings identical; the Next repo
  is read-only. Error *messages* are the exception: translate them to English,
  since the UI is English and the Next routes answer in Portuguese. Generated
  *content* is not a message and is not translated — Policy Generator's policy
  and terms stay in PT-BR, because the document is the tool's product.
  **Why:** the app talks to a local Node sidecar so the tuned image/video/font
  pipelines are reused and stay portable to a future Windows app.

- **Rule:** a new sidecar tool is a file in `Sidecar/tools/`, one line in
  `server.mjs`, and one `case` in whichever view owns the tool —
  `FileToolView.requestFields` for a file tool, the `update<Tool>State()` of
  `FormFieldsSliceA`/`B` for a form tool. No new Swift file, and
  `project.pbxproj` needs no edit — `Sidecar/` is a folder reference.
  **Why:** the shape was chosen so tools 2–26 are mechanical.

- **Rule:** a form tool submits through `NimbusAPIClient.processForm(tool:fields:files:)`
  — multipart with no primary file part, read by the sidecar with the same
  `request.formData()` the file tools already use. A field's value reaches the
  submit because each `update<Tool>State()` writes `fields[…]`/`files[…]`
  (bindings owned by `FormToolView`) in the same place it already set
  `canSubmit`; assigning a `URL?` removes the key when the file is absent.
  **Why:** one wire protocol for the whole sidecar instead of a second JSON
  path, and no state container beyond the `@Binding`s that already existed.

- **Rule:** the sidecar answers an error as `{"error": "..."}`, and
  `NimbusAPIError.errorDescription` extracts that key before display, falling
  back to the raw body when it isn't JSON.
  **Why:** the generic result panel would otherwise print a JSON blob at the
  user — see lessons.md, 2026-09-01.

- **Rule:** a view whose background is glass or vibrancy takes its shadow from
  the window (`hasShadow`), never from SwiftUI's `.shadow`; and a single glass
  element needs no `GlassEffectContainer`.
  **Why:** `.shadow` cannot sample a backdrop composited outside the SwiftUI
  layer and falls back to the bounding box, and the container renders across its
  whole rect — see lessons.md, 2026-08-31.

- **Rule:** a symbol from an SDK newer than the oldest toolchain that must build
  the project goes behind `#if compiler(>=x)`, not just `if #available`.
  **Why:** availability is runtime, symbol resolution is compile time, and CI
  builds on `macos-14` — see lessons.md, 2026-08-31.

- **Rule:** transient panels activate the app but never call
  `setActivationPolicy`; only a real window changes the policy.
  **Why:** an `.accessory` app can already become key and present an open panel;
  flipping the policy just flashes a Dock icon — see lessons.md, 2026-08-31.

- **Rule:** form layout is label-above-field (`FormRow` is the only labeling
  helper); a fixed-width control uses `.frame(width:, alignment: .leading)`, and
  content inside a `ScrollView` keeps a small inset on all sides so borders and
  focus rings are not clipped.
  **Why:** `.frame(width:)` centers a control that hugs its content, and a
  ScrollView clips at its bounds — see lessons.md, 2026-08-31.

- **Rule:** a new source file is added to `Nimbus.xcodeproj/project.pbxproj`
  (build file, file reference, group, Sources phase); check it with
  `plutil -lint`. `Package.swift` needs **no** edit — its target declares
  `path: "Sources/Nimbus"` with no explicit `sources:`, so SwiftPM discovers
  the file on its own.
  **Why:** the project has no synchronized groups, so Xcode alone drifts from
  SwiftPM silently — see lessons.md, 2026-08-31 and 2026-09-01.

- **Rule:** dynamic row lists use `Item: Identifiable` with `ForEach($items)`
  and remove by `id`, never by index.
  **Why:** index identity shifts on removal and corrupts the surviving rows'
  bindings — see lessons.md, 2026-08-31.

- **Rule:** in a form past a handful of fields, split the fields and their
  `.onChange` modifiers into per-section `Group`s.
  **Why:** a long `.onChange` chain on one body blows the Swift type-checker's
  budget — see lessons.md, 2026-08-31.

- **Rule:** a tool's inputs are defined in `docs/tool-inputs.md`; a tool reaches
  the user through `ToolCatalog` plus either `FileToolKind`/`FileToolConfiguration`
  (file-first tools) or `FormToolKind`/`FormToolConfiguration` (form tools).
  `GenericToolView` is a fallback that no catalogued tool should hit.
  **Why:** the three catalogs are decoupled on purpose, so a new tool needs an
  entry in each — see CLAUDE.md, Architecture.
