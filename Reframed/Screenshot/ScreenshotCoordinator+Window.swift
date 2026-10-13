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
  let failure: String?

  init(
    result: ScreenshotResult?,
    capturedIDs: [CGWindowID],
    skipped: Int,
    failure: String? = nil
  ) {
    self.result = result
    self.capturedIDs = capturedIDs
    self.skipped = skipped
    self.failure = failure
  }

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
      present(captured.failure ?? "Those windows are no longer available to capture.")
      restoreFocus(previousApplication)
      previousApplication = nil
      return
    }
    if ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL) {
      ScreenshotFeedbackWindow.show(captured.notice ?? "Copied to clipboard", near: NSEvent.mouseLocation)
    } else {
      present("Could not copy the screenshot to the clipboard.")
    }
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
        results.append(try await captureSession.windowImage(window, includeShadow: includeShadow))
        capturedIDs.append(windowID)
      } catch {
        skipped += 1
      }
    }
    guard let first = results.first else {
      return WindowSetCapture(result: nil, capturedIDs: [], skipped: skipped)
    }
    let scale = first.backingScale > 0 ? first.backingScale : 1
    guard let image = WindowCaptureComposer.compose(results.map(\.image), scale: scale) else {
      return WindowSetCapture(
        result: nil,
        capturedIDs: [],
        skipped: skipped,
        failure: "Those windows are too large to combine into one image."
      )
    }
    let composed = captureSession.adoptComposedWindow(
      image: image,
      displayID: first.displayID,
      scale: scale
    )
    return WindowSetCapture(result: composed, capturedIDs: capturedIDs, skipped: skipped)
  }

  private func finishWindowSetCapture(_ windowIDs: [CGWindowID], includeShadow: Bool) async {
    let captured = await captureWindowImages(windowIDs, includeShadow: includeShadow)
    guard let result = captured.result else {
      isCapturing = false
      frozenDisplays.removeAll()
      present(captured.failure ?? "Those windows are no longer available to capture.")
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
