import AppKit
import CoreGraphics
import ScreenCaptureKit

extension ScreenshotCoordinator {
  func captureWindow() {
    guard admit() else { return }
    previousApplication = NSWorkspace.shared.frontmostApplication
    Task { [weak self] in
      guard let self else { return }
      self.exclusions = await self.resolveExclusions()
      await self.freezeThenSelect()
    }
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
      ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
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
      ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
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
      ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
    } catch {
      present(error.localizedDescription)
    }
  }
}
