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
  let liveFallbacks: Int
  let failure: String?

  init(
    result: ScreenshotResult?,
    capturedIDs: [CGWindowID],
    skipped: Int,
    liveFallbacks: Int = 0,
    failure: String? = nil
  ) {
    self.result = result
    self.capturedIDs = capturedIDs
    self.skipped = skipped
    self.liveFallbacks = liveFallbacks
    self.failure = failure
  }

  var notice: String? {
    var parts: [String] = []
    if skipped > 0 {
      parts.append(skipped == 1 ? "Skipped 1 window" : "Skipped \(skipped) windows")
    }
    if liveFallbacks > 0 {
      parts.append(liveFallbacks == 1 ? "1 window captured live" : "\(liveFallbacks) windows captured live")
    }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
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
    ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
    ScreenshotFeedbackWindow.show(captured.notice ?? "Copied to clipboard", near: NSEvent.mouseLocation)
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  func captureWindowImages(_ windowIDs: [CGWindowID], includeShadow: Bool) async -> WindowSetCapture {
    var shots: [ScreenshotResult] = []
    var capturedIDs: [CGWindowID] = []
    var skipped = 0
    var liveFallbacks = 0
    for windowID in windowIDs {
      do {
        let window = try await captureSession.resolveWindow(id: windowID)
        if let frozen = frozenWindowShot(window, includeShadow: includeShadow) {
          shots.append(frozen)
        } else {
          shots.append(try await captureSession.captureWindow(window, includeShadow: includeShadow))
          if !frozenDisplays.isEmpty {
            liveFallbacks += 1
          }
        }
        capturedIDs.append(windowID)
      } catch {
        skipped += 1
      }
    }
    guard let first = shots.first else {
      return WindowSetCapture(result: nil, capturedIDs: [], skipped: skipped, liveFallbacks: liveFallbacks)
    }
    let scale = first.backingScale > 0 ? first.backingScale : 1
    guard let image = WindowCaptureComposer.compose(shots.map(\.image), scale: scale) else {
      return WindowSetCapture(
        result: nil,
        capturedIDs: [],
        skipped: skipped,
        liveFallbacks: liveFallbacks,
        failure: "Those windows are too large to combine into one image."
      )
    }
    let composed = captureSession.adoptRendered(
      image: image,
      selection: composedSelection(first: first, image: image, scale: scale)
    )
    return WindowSetCapture(result: composed, capturedIDs: capturedIDs, skipped: skipped, liveFallbacks: liveFallbacks)
  }

  private func frozenWindowShot(_ window: SCWindow, includeShadow: Bool) -> ScreenshotResult? {
    guard
      let selection = StillCaptureService.frozenWindowSelection(for: window, includeShadow: includeShadow),
      let frozen = frozenDisplays[selection.displayID]
    else { return nil }
    return try? captureSession.captureFrozenRegion(selection, from: frozen)
  }

  private func composedSelection(first: ScreenshotResult, image: CGImage, scale: CGFloat) -> SelectionRect {
    let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    return SelectionRect(
      rect: CGRect(origin: .zero, size: size),
      displayID: first.displayID,
      displayOrigin: .zero,
      displayHeight: size.height,
      scale: scale
    )
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
