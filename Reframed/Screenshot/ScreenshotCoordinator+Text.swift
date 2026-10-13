import AppKit
import CoreGraphics

extension ScreenshotCoordinator {
  func recognizeText(_ image: CGImage, detailed: Bool) async -> OCRResult {
    do {
      return try await Task.detached(priority: .userInitiated) {
        detailed
          ? try OCRService.recognizeAccurately(in: image)
          : try OCRService.recognizeQuickly(in: image)
      }.value
    } catch {
      return OCRResult(lines: [])
    }
  }

  func annotationCaptureText(_ image: CGImage, _ selection: SelectionRect) {
    let signature = "\(selection.displayID)-\(selection.rect)"
    let detailed = lastTextSelectionSignature == signature
    lastTextSelectionSignature = signature
    adoptAnnotationRegion(image, selection)
    ScreenshotFeedbackWindow.show(
      detailed ? "Reading text in detail..." : "Reading text...",
      near: NSEvent.mouseLocation,
      sticky: true
    )
    let request = scrollingRequest
    Task { @MainActor [weak self] in
      guard let self else {
        ScreenshotFeedbackWindow.dismissCurrent()
        return
      }
      let result = await self.recognizeText(image, detailed: detailed)
      guard self.scrollingRequest == request, self.isCapturing else {
        ScreenshotFeedbackWindow.dismissCurrent()
        return
      }
      if result.lines.isEmpty, !detailed {
        ScreenshotFeedbackWindow.show("No text found - press O again for a detailed read", near: NSEvent.mouseLocation)
        return
      }
      ScreenshotFeedbackWindow.show(self.publishText(result), near: NSEvent.mouseLocation)
      self.finishInlineAnnotation()
    }
  }
}
