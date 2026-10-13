import AppKit
import CoreGraphics

extension ScreenshotCoordinator {
  func recognizeText(_ image: CGImage) async -> AnnotationTextOutcome {
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try OCRService.recognize(in: image)
      }.value
      return result.lines.isEmpty ? .empty : .found(result)
    } catch {
      return .failed
    }
  }

  func annotationCaptureText(
    _ image: CGImage,
    _ selection: SelectionRect,
    completion: @escaping (AnnotationTextOutcome) -> Void
  ) {
    adoptAnnotationRegion(image, selection)
    let progress = ScreenshotFeedbackWindow.show("Reading text...", near: NSEvent.mouseLocation, sticky: true)
    textProgressToken = progress
    let request = scrollingRequest
    Task { @MainActor [weak self] in
      guard let self else {
        completion(.failed)
        return
      }
      let outcome = await self.recognizeText(image)
      guard self.scrollingRequest == request, self.isCapturing else {
        self.textProgressToken = nil
        ScreenshotFeedbackWindow.dismiss(progress)
        completion(.failed)
        return
      }
      self.textProgressToken = nil
      completion(outcome)
      switch outcome {
      case .found(let result):
        ScreenshotFeedbackWindow.show(self.publishText(result), near: NSEvent.mouseLocation)
        self.finishInlineAnnotation()
      case .empty:
        ScreenshotFeedbackWindow.show("No text found", near: NSEvent.mouseLocation)
      case .failed:
        ScreenshotFeedbackWindow.dismiss(progress)
        self.present("Text recognition failed. Try a smaller region.")
      }
    }
  }
}
