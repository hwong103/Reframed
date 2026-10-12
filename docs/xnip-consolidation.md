# Folding Xnip into Reframed

Scope for consolidating the Xnip screenshot-and-annotation workflow into this fork so
one app covers capture, annotate, pin, OCR and export.

Status: proposal, revised after an architecture review (see the Advisor review section
at the end, which corrected two claims and repriced the phases). Not implemented.
Code references were read in this checkout at `feat/rename-blur-and-export-naming`
(commit 144e185) during two inventory passes plus the review.

## Goal

Keep Reframed's recording and video editor as the core, and add a still-image lane next
to it: hotkey or menu bar, select a region, window or screen, annotate, then copy,
save, pin or OCR. The bar is "Xnip is not needed for daily work", not feature parity
with every Xnip release.

## Non-goals

- Xnip's hosted sharing/upload, accounts, subscriptions or watermarks.
- A capture history library (may come later as a small addition).
- Real-time translation; OCR is text extraction to the clipboard only.
- Rewriting the video editor or the recording pipeline.
- Capturing off-Space, minimised, or Reframed's own windows in v1 (declared
  unsupported rather than half-working; see the contract below).

## Capture and output contract

These are P0 decisions, not polish. Every one is cheaper to settle before the first
screenshot ships than after.

1. Capture intent vs target. Separate "still or video" from "region, window or
   display". Today `CaptureMode` mixes them (`State/CaptureMode.swift:1-6`), and
   `State/SessionState+Selection.swift:73-82` always starts a recording on confirm.
   Adding `.screenshot` cases to that enum is the wrong seam.
2. Coordinates. Keep the existing global Quartz-to-AppKit flip as it is: it is the
   standard global conversion, and mixed display heights or negative X origins do not
   invalidate it. `SelectionRect.screenCaptureKitRect`
   (`CaptureModes/Common/SelectionRect.swift:17-24`) is a different operation - a
   global AppKit region converted to display-local Quartz - and both are needed. Add a
   still-specific conversion that snaps edges in pixel space, does not truncate to even
   pixels, and fails loudly when the captured display is missing rather than silently
   using a zero origin or a 2.0 scale.
3. Pixel and colour contract. Capture at native backing scale in SDR sRGB with colour
   metadata embedded, for capture, canvas, export and clipboard alike. Do not inherit
   the recorder's video pixel formats, dynamic range or retina doubling
   (`Recording/ScreenCaptureSession.swift:65-81`). Sharing a renderer does not by
   itself guarantee that preview and export agree across three displays with different
   profiles.
4. Window capture specifics. Decide and document: shadow on or off, alpha, child sheets
   and popovers, clipping when a window hangs off a display, and mixed-scale window
   sizing. Use the content filter's geometry and the point-to-pixel scale, then assert
   the realised output dimensions. Window lookup today covers on-screen layer-zero
   windows and excludes Reframed itself (`App/WindowController.swift:34-84`), and
   shareable-content enumeration is on-screen only (`App/Permissions.swift:28`).
5. Activation. `LSUIElement` is false (`Reframed/Info.plist:15`) and selection
   activates the app, which can dismiss the very menu being photographed. Decide
   whether immediate capture freezes display pixels before activation while delayed
   capture takes fresh pixels after selection, then restore the previous foreground app
   on copy or cancel. Exclude selection overlays, pinned panels, the webcam preview and
   the capture toolbar from every capture.
6. Clipboard and drag. Publish PNG and TIFF from the same sanitized result and verify
   pasting into the apps actually used day to day, rather than assuming PNG alone is
   enough. Finder drag-out needs a file URL or file promise; image-drop destinations
   need image data.
7. Repeat last capture. A hotkey that repeats the previous region without reselecting
   is core Xnip muscle memory. It belongs in P0, and it has to be tracked separately
   from the recording flow's last selection.
8. Sanitized export. Settled: annotations are never persisted as an editable document,
   so nothing on disk or on the pasteboard can leak pixels that a blur was meant to
   destroy. The rule is simply that every output is a flattened render of the sanitized
   canvas, and weak blur is still not a privacy guarantee, so opaque redaction is
   offered as a separate tool.
9. Memory budget. A 2880x5120 display is about 59 MB per 8-bit image, before the
   rendered cache, blur intermediates, clipboard encodings and undo history. Set
   decoded-pixel and resident-memory limits, do not snapshot bitmaps per undo step, and
   bound long-image height.
10. Failure paths. Filename collisions, cancellation during asynchronous capture or
    OCR, OCR language and reading order, hotkey autorepeat, permission grant followed
    by relaunch, and a display unplugged mid-capture.

## Xnip surface to cover

| Feature | Today in Reframed | Plan |
| --- | --- | --- |
| Region / window / full-screen still capture | None. No `SCScreenshotManager`, no `CGWindowListCreateImage`, no image path at all | New, on refactored selection |
| Timed / delayed capture | `TimerDelay` (none/3/5/10s) exists for video (`State/RecordingOptions.swift:22-36`) | Reuse |
| Repeat last capture | Nothing | P0 |
| Scrolling (long) capture | Nothing. No stitch, no registration, no scroll source | P4 feasibility spike, constrained |
| Annotate: arrow, rectangle, ellipse, line, pen, highlighter, text, numbered steps, blur/pixelate, crop | None. The region model is seconds-keyed and video-only (`Project/ProjectMetadata.swift`) | New model plus canvas; core set first |
| Drag out, numbered step tool | Nothing | Move earlier than "polish" if these are daily workflows |
| Beautify: padding, shadow, background, rounded border | Background styles exist for video | After the core tools |
| Colour picker, ruler / measure | Colour tokens and pickers exist (`UI/Colors.swift`, `UI/TailwindColorPicker.swift`) | Later, small |
| Pin screenshot always on top | NSPanel pattern exists (`Recording/WebcamPreviewWindow.swift:150-175`) but sets no collection behaviour | Reuse the pattern; define Spaces and full-screen behaviour |
| OCR / text snip | Vision imported for person segmentation only (`Compositor/PersonSegmentationProcessor.swift:3,69`); no `VNRecognizeTextRequest` | New service, small |
| Copy image to clipboard / save PNG | Clipboard write copies a file URL (`Compositor/ExportSheet+Phases.swift:149-155`); no image encoder anywhere | New ImageIO writer plus PNG+TIFF pasteboard |
| Hotkey + menu bar entry | `KeyboardShortcutManager` global CGEvent tap plus a local monitor; `MenuBarView` quick actions | Reuse, but the tap is gated to recording states |

## Architecture

New module, `Reframed/Screenshot/`, for the still-specific models and rendering:

- `AnnotationDocument` - source image reference, immutable pixel dimensions,
  coordinate convention, colour-space policy, crop transform, plus an ordered array of
  annotation items with geometry, style and z-order. Codable. The single source of
  truth, and the object the sanitized-export rule is enforced against.
- `AnnotationRenderer` - draws a document into a `CGContext`; the on-screen canvas and
  the exported image both call it.
- `AnnotationCanvasView` - AppKit `NSView` (finer hit-testing than SwiftUI `Canvas` for
  handles and freehand), hosted in SwiftUI. Live strokes draw in a separate overlay
  layer; only committed operations re-render the base.
- `AnnotationToolbar` - SwiftUI, built from existing components (`PrimaryButtonStyle`,
  `OutlineButtonStyle`, `IconButton`, `SegmentPicker`, `SwatchButton`,
  `TailwindColorPicker`, `SliderRow`).
- `StillCaptureService` - `SCScreenshotManager` with a filter and configuration built
  for stills, honouring the contract above.
- `ImageExporter` - ImageIO writer (PNG/JPEG) plus PNG and TIFF pasteboard data and
  file-promise drag-out.
- `PinWindowController` - borderless non-activating `NSPanel` with a deliberate level,
  `hidesOnDeactivate` policy and collection behaviour for Spaces and full-screen apps;
  position persisted through `StateService`.
- `OCRService` - `VNRecognizeTextRequest` over a whole image or a dragged text region.
- `ScreenshotSession` - `@Observable`, owns the still flow, deliberately outside the
  recording state machine.

Shared interaction, refactored rather than borrowed:

- The selection overlays are not reusable as-is. `SelectionCoordinator.beginSelection`
  takes `SessionState` and activates the app
  (`CaptureModes/Common/SelectionCoordinator.swift:8`), the area controls build
  `CaptureAreaView(session:)`
  (`CaptureModes/CaptureArea/SelectionOverlayView+Controls.swift:39`), and both region
  and window confirmation create recording borders and begin recording
  (`State/SessionState+Selection.swift:73-82`). `SessionState.transition` also carries
  camera, audio and window-tracking side effects (`State/SessionState.swift:61`).
- Move the reusable selection interaction into `CaptureModes/Common/` with
  confirm/cancel callbacks and injected controls, so both the recorder and the still
  flow drive it without either owning the other's state.
- Give selection overlays and shortcut routing an explicit owner with a stated policy
  for a screenshot request that arrives during recording, countdown, processing or
  editing.
- `Utilities/KeyboardShortcut.swift:113-180` gains still-capture actions, and the tap
  gate at `State/KeyboardShortcutManager.swift:89-94` widens per action through an
  allowlist rather than by removing the gate, or stop and pause would fire while idle.
- `UI/MenuBarView.swift:42-91` and `UI/CaptureToolbar+ModeSelection.swift:27-70` gain
  entries; `UI/SettingsView.swift:4-11` gains a screenshot tab.

## Phases and retirement criteria

Every phase ends with a CI artifact installed over `/Applications/Reframed.app` and a
live acceptance pass with a real mouse. Sizing assumes one focused workstream and no
surprises in the capture contract; treat the first integrated cycle as the calibration
point rather than trusting these numbers.

P0 - capture and contract. About one week, not a couple of days once the contract items
are honoured. Region, window and screen stills to clipboard and disk, hotkey plus menu
bar, repeat-last, selection shared by callback, PNG and TIFF publishing, activation and
foreground-restoration rules, and the coordinate and colour contract settled. No
annotation. Acceptance: hotkey to region to paste into a named destination app at the
correct pixel size on each of the three displays; window capture with the declared
shadow and clipping behaviour; repeat-last works without reselecting; a cancelled
capture changes nothing.

P1 - annotation core. Two to four weeks, the bulk of the work. Arrow, rectangle,
ellipse, line, pen, highlighter, text, blur/pixelate, crop; toolbar with colours and
widths; undo/redo as its own lightweight command stack; copy and save with annotations
baked in. Acceptance: annotate, undo, crop, blur, copy, paste elsewhere and confirm
pixels match the canvas at 100%; redaction destroys the underlying pixels in every
output. Drag-out lands here (decided); the numbered step tool stays in P3.

P2 - OCR and pinning. About a week. Whole-image and text-snip OCR to the clipboard, and
pinned panels that behave defined-ly across Spaces, full-screen apps, Mission Control,
multiple pins and display changes. Acceptance: OCR against named fixtures with expected
text; a pin survives app switching and full-screen apps and restores its position.

P3 - polish. About a week. Padding, shadow, background and rounded border reusing the
video background styles, colour picker, ruler, recent captures strip.

P4 - scrolling capture, as a spike after P1 (decided). Several days to a feasibility
spike, then decide from measured seam quality rather than from the spike finishing. The
cheap honest version is user-driven: record a fixed region while scrolling with
deliberate overlaps, import the raw screen track, crop fixed headers, propose seams,
let the user correct them, and refuse uncertain joins. No automatic scrolling, no end
detection, and no promise of a clean stitched page on lazy-loaded content.

Retirement criterion for Xnip: the owner's named daily workflows pass end to end -
capture, annotate, copy, save, and paste into the real destination apps. Not "P1
merged". Keep Xnip installed until then, and keep it specifically for long pages if the
P4 spike fails.

Total: roughly five to nine weeks of focused work for a narrowed workflow; nothing
credible lands under a month. An earlier draft's "two weeks to Xnip-redundant" was
optimistic.

## Reuse, after adaptation

- Selection overlays per display, crosshair, resize handles, remember-last-rect: reuse
  requires the callback refactor described above, not free reuse.
- Per-display coordinate handling: `CaptureModes/Common/SelectionRect.swift:17-28`,
  plus the still-specific conversion from the contract.
- Window lookup and cycling: `App/WindowController.swift:34-186`.
- Permission gating: `App/Permissions.swift:6-30`.
- Menu bar shell, quick actions, rebindable shortcuts, config and state services.
- Styling tokens and controls under `UI/` (colours, constants, buttons, pickers,
  sliders, toggles, section headers).
- Floating panel construction and position persistence:
  `Recording/WebcamPreviewWindow.swift:150-175`.
- Frame to `CGImage`: `Compositor/FrameRenderer+Helpers.swift:316`. Useful for offline
  stitching; not needed for direct still capture.

## Decisions

Settled by the owner on 2026-10-13:

1. Scrolling capture: feasibility spike after P1, gated on measured seam quality, and
   keep Xnip installed for long pages if the spike fails.
2. Annotations are not re-editable. Bake them into the exported image; no annotation
   sidecar and no persisted editable document. This removes the whole class of
   redaction-leak concerns in contract item 8, because there is no editable source
   containing unredacted pixels to write out.
3. Screenshot naming: default `Screenshot-2026-10-13-101027.png` in the existing output
   folder, overridable by a prefix setting.
4. Screenshots do not become `.frm` projects. Standalone files; an "open in editor"
   action can come later if it turns out to be useful.
5. Repeat-last capture is in P0. Drag-out is in P1.
6. Xnip is retired when the named daily workflows pass end to end, not at a phase
   boundary.

Still open:

1. The numbered step tool and the ruler: confirm they are wanted before building them
   in P3 rather than adding them by default.

## Risks

- Shared selection state. The overlays currently assume a recording session; a still
  flow bolted onto them can flip recording state, show a recording border, or disturb
  an in-flight recording. This is why the callback refactor is P0.
- Undo/redo does not generalise. `Editor/History.swift:3-70` stores whole
  `EditorStateData` snapshots on a 1.5 second debounce capped at 50
  (`EditorState+Persistence.swift:338`). Annotation needs its own command stack.
- The compositor is timeline-gated. `Compositor/FrameRenderer.swift:78,190` keys every
  draw to `compositionTime`; static annotations must not be folded into it.
- Coordinate conversion. Mixed display heights are fine for the existing global flip;
  the real risks are pixel-edge rounding, even-pixel truncation inherited from video,
  cross-display selections, and displays appearing or disappearing mid-capture.
- No image encoder exists, so PNG/TIFF and pasteboard writes are net-new and gate P0.
- Redaction is a privacy guarantee, not a visual effect.
- Memory and long images. See the contract; 59 MB is one image, not the working set.
- Ad-hoc signing tax. Every install is a new signature, so Screen Recording needs
  re-approval; a stable local signing identity should land before this work starts
  because it means several builds.

## Verification

- Build through `.github/workflows/build.yml` and install the artifact over
  `/Applications/Reframed.app`; confirm signature, version, launch.
- The CI workflow builds, signs and packages but runs no test suite; a green build is
  not acceptance.
- Automated UI driving of Reframed windows is unreliable here (the automation resolves
  clicks as accessibility presses and cannot hit-test this window layout), so pixel and
  interaction acceptance is done by the user with a real mouse. I verify build,
  install, plumbing, file output, and anything checkable from disk or the clipboard.

## Advisor review

An independent architecture review (gpt-6.1-sol) returned: approve the consolidation
direction, revise before turning it into a work queue. Its substantive corrections are
folded in above: the selection overlays are not free reuse and need callback-based
shared ownership with intent and target separated; the first draft's multi-display
Y-flip diagnosis was wrong, and the real contract question is pixel-edge snapping and
display loss, not mixed heights; annotation documents need a source-image,
colour-space and redaction contract rather than a bare canvas size; pinning needs
explicit Spaces and full-screen behaviour rather than inheriting the webcam panel's
defaults; and offline video stitching is sound only as a constrained,
user-corrected feature. It also repriced the phases: about a week for integrated P0, two
to four weeks for the full annotation set, five to nine weeks for a narrowed whole, and
Xnip retired only after named daily workflows pass.
