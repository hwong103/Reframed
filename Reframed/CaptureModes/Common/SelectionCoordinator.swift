import AppKit

@MainActor
struct SelectionAnnotationHandlers {
  let copy: (CGImage, SelectionRect) -> Void
  let save: (CGImage, SelectionRect) -> Void
  let saveAndCopy: (CGImage, SelectionRect) -> Void
  let captureText: (CGImage, SelectionRect) -> Void
  let pin: (CGImage, SelectionRect) -> Void
  let openInWindow: (CGImage, SelectionRect) -> Void
  let openInPreview: (CGImage, SelectionRect) -> URL?
  let finish: () -> Void
  let finishWithoutRefocus: () -> Void
  let cancel: () -> Void
}

/// Everything an area-selection overlay needs from its owner.
///
/// Deliberately session-free so a still-capture flow can reuse region
/// selection without owning a `SessionState`.
@MainActor
struct SelectionRequest {
  let timerDelay: Int
  let confirmTitle: String?
  let hint: String
  let backgroundImages: [CGDirectDisplayID: CGImage]
  let initialFullScreen: Bool
  let hoverTargetsEnabled: Bool
  let annotation: SelectionAnnotationHandlers?
  let onCountdownStart: () -> Void
  let onConfirm: (SelectionRect) -> Void
  let onConfirmWindow: ((CGWindowID, CGRect) -> Void)?
  let onCancel: () -> Void

  init(
    timerDelay: Int,
    confirmTitle: String? = nil,
    hint: String = "Shift to lock aspect ratio \u{00b7} Esc to cancel \u{00b7} Enter to start",
    backgroundImages: [CGDirectDisplayID: CGImage] = [:],
    initialFullScreen: Bool = false,
    hoverTargetsEnabled: Bool = false,
    annotation: SelectionAnnotationHandlers? = nil,
    onCountdownStart: @escaping () -> Void,
    onConfirm: @escaping (SelectionRect) -> Void,
    onConfirmWindow: ((CGWindowID, CGRect) -> Void)? = nil,
    onCancel: @escaping () -> Void
  ) {
    self.timerDelay = timerDelay
    self.confirmTitle = confirmTitle
    self.hint = hint
    self.backgroundImages = backgroundImages
    self.initialFullScreen = initialFullScreen
    self.hoverTargetsEnabled = hoverTargetsEnabled
    self.annotation = annotation
    self.onCountdownStart = onCountdownStart
    self.onConfirm = onConfirm
    self.onConfirmWindow = onConfirmWindow
    self.onCancel = onCancel
  }
}

@MainActor
final class SelectionCoordinator {
  private var overlayWindows: [SelectionOverlayWindow] = []
  private var borderWindow: RecordingBorderWindow?

  func beginSelection(request: SelectionRequest) {
    let pointerDisplayID = request.initialFullScreen ? NSScreen.displayID(for: NSEvent.mouseLocation) : nil
    let hoverProvider = request.hoverTargetsEnabled ? HoverTargetProvider() : nil
    for screen in NSScreen.screens {
      let isInitialActive = request.initialFullScreen && screen.displayID == pointerDisplayID
      let window = SelectionOverlayWindow(
        screen: screen,
        request: request,
        isInitialActive: isInitialActive,
        hoverProvider: hoverProvider
      )
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
