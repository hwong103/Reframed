# Screenshot lane contract

Decisions that P0 must honour before any screenshot ships. Companion to
`docs/xnip-consolidation.md`; that document is the plan, this one is the spec the code
is held to. Requirements are numbered so reviews and tests can cite them.

## Scope

P0 delivers region, window and full-display stills to the clipboard and to disk, with a
hotkey, a menu bar entry and repeat-last. No annotation, no OCR, no pinning. Those come
in later phases.

## R1 - intent, target and ownership

R1.1 Capture intent (still or video) is separate from the capture target (region,
window, display). Do not add screenshot cases to the recording mode enum.
R1.2 The still flow owns its own state. It must not read or write `SessionState` or
`CaptureState`, and a screenshot must never change recording state.
R1.3 Region and window selection are shared interaction, driven by callbacks
(confirm/cancel) with the values the overlay needs injected. Neither the recorder nor
the still flow owns the other's session.
R1.4 A capture request that arrives while recording, counting down, processing or
editing is refused with a visible reason. It is never silently queued.

## R2 - coordinates and pixels

R2.1 The existing global Quartz-to-AppKit flip stays as it is; mixed display heights and
negative display origins are supported by it and must not be "fixed".
R2.2 A still converts its selection to display-local Quartz through `SelectionRect`,
snapping edges in pixel space. No even-pixel truncation, no retina doubling.
R2.3 An unresolvable display is an error the user sees, never a zero origin or a
hardcoded scale.
R2.4 Capture is at the display's native backing scale, SDR sRGB, with colour metadata
embedded in the written file.
R2.5 Cross-display selections are not supported in P0; the selection is clamped to the
display containing its midpoint, and the behaviour is stated in the UI.

## R3 - window capture

R3.1 Window capture uses the content filter's geometry with the window's own scale, and
the realised output size is asserted rather than assumed.
R3.2 Shadow is off and alpha is opaque by default. Both are recorded here so the result
is reproducible, not accidental.
R3.3 Child sheets and popovers belonging to the window are included; content clipped by
the display edge is clipped, not rescaled.
R3.4 Unsupported in P0 and surfaced as such: windows on other Spaces, minimised
windows, and Reframed's own windows.
R3.5 Our own chrome - selection overlays, pinned panels, webcam preview, capture
toolbar - is excluded from every capture.

## R4 - activation and focus

R4.1 Region and window selection activate Reframed because the overlays need focus.
R4.2 Capture freezes first, selection second, in the Xnip and CleanShot shape: the
display is captured before the overlays appear, the frozen image is shown dimmed as the
overlay background, and the drag selects a region on that frozen image. Consequences
that are now required, not optional: an open menu or sheet survives the capture, an
animation cannot move between selection and capture, and the pixels copied are exactly
the pixels seen under the selection.
R4.3 After copy or cancel, focus returns to the app that was frontmost before the
capture started.
R4.4 The still flow does not touch microphone, camera or accessibility permissions;
Screen Recording alone gates it.
R4.5 R4.2 governs region capture. Window capture is a separate, live contract: the
frozen backdrop is used only to choose the target window, and the window itself is
re-rendered in isolation when the selection is confirmed, so the result keeps the
window's own transparency, corner rounding and shadow, and never includes an
overlapping window. An animation inside a captured window can therefore differ from
the frozen preview; that is accepted in exchange for an isolated, composited window.

## R9 - inline annotation after confirm

The Xnip shape: confirming a selection does not tear the overlay down, and there is no
separate annotation window in the default flow.

R9.1 Confirm keeps the frozen overlay on screen: the selected area stays undimmed and
everything outside it dims. Annotation is drawn in place on that frozen surface, clipped
to the selection.
R9.2 The selection stays resizable while annotating. Annotations live in the frozen
image's pixel space, so enlarging the area reveals more of the frozen screen and keeps
the marks where they were drawn. Only the crop that Copy and Save apply changes.
R9.3 Copy/Save/Capture Text/Pin all render the annotations and crop to the current
selection. The rendered result is what is published, written and pinned.
R9.4 The toolbar is a light, near-white rounded pill with dark grey icons; the active
tool is drawn in the accent blue and other tools sit in dark grey. It hangs directly
below the selection, centred on it; when there is no room below (the full-screen
default) it drops inside the selection near its bottom edge, clamped to the screen's
visible frame, and it never jumps to the top of the screen. The toolbar and the frozen
overlay are both excluded from capture.
R9.5 A blue capsule badge on the selection's top-left reads `width x height pt` with an
inline aspect-lock glyph, and a white circular button with a dark cross floats at the
selection's top-right for cancel. The thin accent-blue outline and the corner handles
stay visible above the annotation surface.
R9.6 Tool shortcuts are backtick for Selection, 1-9 for Rectangle, Oval, Line, Arrow,
Freehand, Pixelate, Text, Step and Highlight; actions are O (Capture Text), T (Pin),
P (Open in Preview), W (Open in Window), Command-S (Save), Shift-Command-S (Save and
Copy), Return/Space (Copy), Command-Z (Undo, Shift-Command-Z redo), Delete (remove the
selected annotation) and Esc (Cancel). Scrolling capture (S) is shown dimmed with a
tooltip rather than hidden.
R9.7 `AnnotationEditorWindowController` is not presented by the default flow. W is the
only opt-in path to a separate window, and it opens the already-rendered result.
R9.8 `ScreenshotActionBarWindow` is retained but never presented; the feedback HUD stays
the only transient message surface. If the action bar is ever presented again it belongs
at the bottom-centre of the capture's screen, above the visible frame's bottom edge and
clamped on screen, regardless of where the capture sits.
R9.9 Escape cancels annotation, writes nothing, and returns focus to the app that was
frontmost before the capture started.
R9.10 The colour control opens a popover holding the current colour, a two-row swatch
grid, opacity, thickness and size sliders, and "Set as Default Style", which persists the
style for the next capture.

## R5 - output

R5.1 Clipboard publishes PNG and TIFF rendered from the same sanitized image, plus a
file URL when a file has been written.
R5.2 Save writes `Screenshot-yyyy-MM-dd-HHmmss.png` into the configured output folder
with a configurable prefix, default `Screenshot`.
R5.3 Name collisions append `-2`, `-3` before the extension; nothing is overwritten.
R5.4 A failed write reports the underlying error; no silent success.

## R6 - repeat last

R6.1 Repeat-last reuses the previous still target without reselecting, and is tracked
separately from the recorder's remembered selection.
R6.2 Repeat-last with no previous target does nothing visible except a short
explanation.

## R7 - hotkeys and entry points

R7.1 Defaults, all rebindable through the existing shortcut settings: **Command-Shift-5
for the main capture**, window `Option-Shift-5`, display `Option-Shift-3`, repeat last
`Option-Shift-R`, save last `Option-Shift-S`. Command-Shift-5 shadows the system
screenshot toolbar while Reframed is running, which is what Xnip does; the tap must
consume the event so the system UI does not also open, and the setting must be
rebindable so the system behaviour can be restored.
R7.2 The global shortcut gate is widened per action through an explicit allowlist, so
stop, pause and restart still only fire during a session.
R7.3 Menu bar gains the same four actions under Quick Actions.

## R8 - robustness

R8.1 Cancelling during an in-flight capture leaves no window, no border and no state
behind.
R8.2 Missing Screen Recording permission routes to the existing permissions UI and the
request is not retried in a loop.
R8.3 Hotkey autorepeat does not start overlapping captures; a second request while one
is in flight is ignored.
R8.4 Resident memory stays bounded: one decoded source image at a time in P0, no bitmap
snapshots retained for undo, and a stated ceiling for future long images.

## Non-goals in P0

Annotation, OCR and pinning were P0 non-goals and now have their own sections (R9, R11,
R10). Still out of scope: scrolling capture (present as a disabled toolbar affordance),
drag-out, beautify, ruler, and a capture history list.

## R10 - pin to screen

R10.1 A pin is a borderless, non-activating `NSPanel` at level `.floating`: above ordinary
app windows and full-screen content, but below Reframed's transient action bar and
feedback HUD (`.screenSaver`), so those are never obstructed.
R10.2 A pin joins all Spaces and full-screen apps through
`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`.
R10.3 Multiple pins coexist; each one is independent.
R10.4 A pin is movable by dragging its image, and resizes by scroll with the aspect ratio
preserved and bounded min/max sides. Escape and a hover close affordance both dismiss it.
R10.5 Each pin's position and size persist through `StateService` and are restored on
launch. If a pin's display is absent at launch, that pin is dropped rather than
mis-placed.
R10.6 Every pin sets `sharingType = .none`, so a pin never appears inside a later capture.

## R11 - OCR scope

R11.1 Text recognition uses `VNRecognizeTextRequest` at `.accurate` with automatic
language detection, restricted to plain text only: no translation.
R11.2 Reading order (top-to-bottom, left-to-right) is a heuristic over Vision
observations; multi-column layouts can reorder.
R11.3 An image with no text returns an empty result, never an error.
R11.4 Text capture from the annotate toolbar recognises off the main actor and holds the
overlay open until the result is ready, then tears down exactly once. The overlay is drawn
at 1:1 device pixels, so the canvas layer's `contentsScale` is pinned to the display
backing scale and the canvas offset is snapped to the device-pixel grid; the visible crop
therefore matches what Copy and Save export. The renderer's `.none` interpolation is load
bearing for the on-screen downscale and must stay `.none`; `AnnotationRenderer.makeImage`
renders at document pixel size and is unaffected. Cancelling while recognition is in
flight wins, and the late result is dropped.
