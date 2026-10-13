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

  func confirmWindowTarget(_ windowID: CGWindowID, rect: CGRect) {
    selectionCoordinator.destroyAll()
    Task { await finishWindowTargetCapture(windowID: windowID, fallbackRect: rect) }
  }

  private func finishWindowTargetCapture(windowID: CGWindowID, fallbackRect: CGRect) async {
    defer {
      isCapturing = false
      frozenDisplays.removeAll()
    }
    do {
      let window = try await captureSession.resolveWindow(id: windowID)
      let result = try await captureSession.captureWindow(window)
      ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
      showActionBar(near: actionBarAnchor(for: window))
    } catch {
      await captureFrozenFallback(fallbackRect)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  private func captureFrozenFallback(_ rect: CGRect) async {
    let displayID = NSScreen.displayID(for: CGPoint(x: rect.midX, y: rect.midY))
    let selection = SelectionRect(rect: rect, displayID: displayID)
    do {
      let result = try await capturedRegion(selection)
      ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
      showActionBar(near: rect)
    } catch {
      present(error.localizedDescription)
    }
  }
}
