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
    windowCaptureRequest += 1
    let request = windowCaptureRequest
    Task {
      await finishWindowSetCapture(
        windowIDs,
        includeShadow: includeShadow,
        frozenTargets: frozenHoverTargets,
        request: request
      )
    }
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
      RecentCaptureStore.shared.record(image: result.image, filename: ScreenshotNaming.previewName())
      ScreenshotFeedbackWindow.show(captured.notice ?? "Copied to clipboard", near: NSEvent.mouseLocation)
    } else {
      present("Could not copy the screenshot to the clipboard.")
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  func captureWindowImages(
    _ windowIDs: [CGWindowID],
    includeShadow: Bool,
    frozenTargets: [HoverTarget] = []
  ) async -> WindowSetCapture {
    var results: [ScreenshotResult] = []
    var capturedIDs: [CGWindowID] = []
    var skipped = 0
    var firstFailure: String?
    for windowID in windowIDs {
      do {
        let window = try await captureSession.resolveWindow(id: windowID)
        results.append(
          try await captureSession.windowImage(
            window,
            includeShadow: includeShadow,
            excludingApplications: exclusions
          )
        )
        capturedIDs.append(windowID)
      } catch {
        if let target = frozenTargets.first(where: { $0.windowID == windowID && $0.layer != 0 }),
          let frozen = frozenDisplays[
            NSScreen.displayID(for: CGPoint(x: target.bounds.midX, y: target.bounds.midY))
          ],
          let fallback = try? frameService.cropFrozenWindow(target, from: frozen)
        {
          results.append(fallback)
        } else {
          firstFailure = firstFailure ?? error.localizedDescription
          skipped += 1
        }
      }
    }
    guard let first = results.first else {
      return WindowSetCapture(
        result: nil,
        capturedIDs: [],
        skipped: skipped,
        failure: firstFailure
      )
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

  private func finishWindowSetCapture(
    _ windowIDs: [CGWindowID],
    includeShadow: Bool,
    frozenTargets: [HoverTarget],
    request: Int
  ) async {
    let captured = await captureWindowImages(
      windowIDs,
      includeShadow: includeShadow,
      frozenTargets: frozenTargets
    )
    guard request == windowCaptureRequest else { return }
    frozenHoverTargets.removeAll()
    guard let result = captured.result else {
      isCapturing = false
      frozenDisplays.removeAll()
      selectionCoordinator.destroyAll()
      present(captured.failure ?? "Those windows are no longer available to capture.")
      restoreFocus(previousApplication)
      previousApplication = nil
      return
    }
    lastWindowSelection =
      captured.capturedIDs.isEmpty
      ? nil
      : WindowSetSelection(windowIDs: captured.capturedIDs, includeShadow: includeShadow)
    if let notice = captured.notice {
      ScreenshotFeedbackWindow.show(notice, detail: "Captured the rest", near: NSEvent.mouseLocation)
    }
    selectionCoordinator.enterComposedAnnotation(image: result.image, displayID: result.displayID)
  }
}
