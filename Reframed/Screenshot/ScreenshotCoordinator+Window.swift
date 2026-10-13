import AppKit
import CoreGraphics
import ScreenCaptureKit

extension ScreenshotCoordinator {
  func captureWindow() {
    guard admit() else { return }
    previousApplication = NSWorkspace.shared.frontmostApplication
    let coordinator = WindowSelectionCoordinator()
    windowSelectionCoordinator = coordinator
    coordinator.beginSelection(
      request: WindowSelectionRequest(
        confirmTitle: "Capture",
        hint: "Tab to cycle windows \u{00b7} Esc to cancel \u{00b7} Enter to capture",
        onConfirm: { [weak self] window in self?.confirmWindow(window) },
        onCancel: { [weak self] in self?.cancelWindowSelection() }
      )
    )
  }

  func confirmWindow(_ window: WindowInfo) {
    windowSelectionCoordinator?.destroyOverlay()
    windowSelectionCoordinator = nil
    Task { await finishWindowCapture(windowID: CGWindowID(window.id)) }
  }

  func cancelWindowSelection() {
    windowSelectionCoordinator?.destroyOverlay()
    windowSelectionCoordinator = nil
    cancel()
  }

  private func finishWindowCapture(windowID: CGWindowID) async {
    defer { isCapturing = false }
    do {
      let window = try await captureSession.resolveWindow(id: windowID)
      let result = try await captureSession.captureWindow(window)
      ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
      showActionBar(near: actionBarAnchor(for: window))
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  private func actionBarAnchor(for window: SCWindow) -> CGRect {
    let frame = window.frame
    return CGRect(
      x: frame.origin.x,
      y: NSScreen.primaryScreenHeight - frame.origin.y - frame.height,
      width: frame.width,
      height: frame.height
    )
  }
}
