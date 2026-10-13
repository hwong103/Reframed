import AppKit
import CoreGraphics
import ScreenCaptureKit

struct WindowSetSelection {
  let windowIDs: [CGWindowID]
  let includeShadow: Bool
}

struct WindowSetCapture {
  let result: ScreenshotResult?
  let capturedIDs: [CGWindowID]
  let skipped: Int

  var notice: String? {
    guard skipped > 0 else { return nil }
    return skipped == 1 ? "Skipped 1 window" : "Skipped \(skipped) windows"
  }
}

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

  func confirmWindowSet(_ windowIDs: [CGWindowID], includeShadow: Bool) {
    Task { await finishWindowSetCapture(windowIDs, includeShadow: includeShadow) }
  }

  func repeatWindowSet(_ selection: WindowSetSelection) async {
    defer { isCapturing = false }
    let captured = await captureWindowImages(selection.windowIDs, includeShadow: selection.includeShadow)
    guard let result = captured.result else {
      present("Those windows are no longer available to capture.")
      restoreFocus(previousApplication)
      previousApplication = nil
      return
    }
    ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
    ScreenshotFeedbackWindow.show(captured.notice ?? "Copied to clipboard", near: NSEvent.mouseLocation)
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  func captureWindowImages(_ windowIDs: [CGWindowID], includeShadow: Bool) async -> WindowSetCapture {
    var results: [ScreenshotResult] = []
    var capturedIDs: [CGWindowID] = []
    var skipped = 0
    for windowID in windowIDs {
      do {
        let window = try await captureSession.resolveWindow(id: windowID)
        let result = try await captureSession.captureWindow(window, includeShadow: includeShadow)
        results.append(result)
        capturedIDs.append(windowID)
      } catch {
        skipped += 1
      }
    }
    guard let first = results.first else {
      return WindowSetCapture(result: nil, capturedIDs: [], skipped: skipped)
    }
    let image = WindowCaptureComposer.compose(results.map(\.image), scale: first.backingScale) ?? first.image
    let scale = first.backingScale
    let composed = ScreenshotResult(
      image: image,
      displayID: first.displayID,
      pointSize: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale),
      backingScale: scale
    )
    return WindowSetCapture(result: composed, capturedIDs: capturedIDs, skipped: skipped)
  }

  private func finishWindowSetCapture(_ windowIDs: [CGWindowID], includeShadow: Bool) async {
    let captured = await captureWindowImages(windowIDs, includeShadow: includeShadow)
    guard let result = captured.result else {
      isCapturing = false
      frozenDisplays.removeAll()
      present("Those windows are no longer available to capture.")
      restoreFocus(previousApplication)
      previousApplication = nil
      return
    }
    lastWindowSelection = WindowSetSelection(windowIDs: captured.capturedIDs, includeShadow: includeShadow)
    if let notice = captured.notice {
      ScreenshotFeedbackWindow.show(notice, detail: "Captured the rest", near: NSEvent.mouseLocation)
    }
    selectionCoordinator.enterComposedAnnotation(image: result.image, displayID: result.displayID)
  }
}
