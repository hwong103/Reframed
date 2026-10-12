import AppKit

/// Everything an area-selection overlay needs from its owner.
///
/// Deliberately session-free so a still-capture flow can reuse region
/// selection without owning a `SessionState`.
@MainActor
struct SelectionRequest {
  let timerDelay: Int
  let onCountdownStart: () -> Void
  let onConfirm: (SelectionRect) -> Void
  let onCancel: () -> Void

  init(
    timerDelay: Int,
    onCountdownStart: @escaping () -> Void,
    onConfirm: @escaping (SelectionRect) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.timerDelay = timerDelay
    self.onCountdownStart = onCountdownStart
    self.onConfirm = onConfirm
    self.onCancel = onCancel
  }
}

@MainActor
final class SelectionCoordinator {
  private var overlayWindows: [SelectionOverlayWindow] = []
  private var borderWindow: RecordingBorderWindow?

  func beginSelection(request: SelectionRequest) {
    for screen in NSScreen.screens {
      let window = SelectionOverlayWindow(screen: screen, request: request)
      overlayWindows.append(window)
      window.orderFrontRegardless()
    }
    overlayWindows.first?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func restoreSelection(_ globalRect: CGRect, displayID: CGDirectDisplayID) {
    guard let screen = NSScreen.screen(for: displayID) else { return }
    guard
      let window = overlayWindows.first(where: {
        $0.frame.contains(screen.frame.origin)
      })
    else { return }
    guard let overlayView = window.contentView as? SelectionOverlayView else { return }

    let localRect = CGRect(
      x: globalRect.origin.x - screen.frame.origin.x,
      y: globalRect.origin.y - screen.frame.origin.y,
      width: globalRect.width,
      height: globalRect.height
    )
    overlayView.applyExternalRect(localRect)
  }

  func showRecordingBorder(screenRect: CGRect) {
    destroyOverlay()
    let window = RecordingBorderWindow(screenRect: screenRect)
    borderWindow = window
    window.orderFrontRegardless()
  }

  func updateRecordingBorder(screenRect: CGRect) {
    borderWindow?.updateCaptureRect(screenRect: screenRect)
  }

  func destroyOverlay() {
    for window in overlayWindows {
      window.orderOut(nil)
      window.contentView = nil
    }
    overlayWindows.removeAll()
  }

  func destroyAll() {
    destroyOverlay()
    borderWindow?.orderOut(nil)
    borderWindow = nil
  }
}
