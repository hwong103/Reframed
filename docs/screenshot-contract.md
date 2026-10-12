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

## R9 - post-capture action bar

The Xnip flow ends in a small bar offering annotate, copy, and save-and-copy. Ours
matches that shape:

R9.1 `Copy` publishes to the clipboard and writes no file. This is the default action
and the current behaviour.
R9.2 `Save & Copy` writes the PNG into the configured output folder and publishes the
same image, plus its file URL, to the clipboard.
R9.3 `Annotate` opens the annotation canvas (phase P1). Until P1 lands the button is
either absent or visibly disabled; it is never a no-op.
R9.4 Escape dismisses the bar and leaves no file and no clipboard change beyond what
the action already did.
R9.5 The bar appears near the capture, does not take focus, and is excluded from any
further capture.

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

Annotation, OCR, pinning, scrolling capture, drag-out, beautify, ruler, numbered steps,
and a capture history list.
