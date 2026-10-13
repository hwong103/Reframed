import AppKit
import CoreGraphics

extension ScreenshotCoordinator {
  func recognizeText(_ image: CGImage, detailed: Bool) async -> AnnotationTextOutcome {
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        detailed
          ? try OCRService.recognizeAccurately(in: image)
          : try OCRService.recognizeQuickly(in: image)
      }.value
      return result.lines.isEmpty ? .empty : .found(result)
    } catch {
      return .failed
    }
  }

  func annotationCaptureText(
    _ image: CGImage,
    _ selection: SelectionRect,
    detailed: Bool,
    completion: @escaping (AnnotationTextOutcome) -> Void
  ) {
    adoptAnnotationRegion(image, selection)
    let progress = ScreenshotFeedbackWindow.show(
      detailed ? "Reading text in detail..." : "Reading text...",
      near: NSEvent.mouseLocation,
      sticky: true
    )
    let request = scrollingRequest
    Task { @MainActor [weak self] in
      guard let self else {
        completion(.failed)
        return
      }
      let outcome = await self.recognizeText(image, detailed: detailed)
      guard self.scrollingRequest == request, self.isCapturing else {
        ScreenshotFeedbackWindow.dismiss(progress)
        completion(.failed)
        return
      }
      completion(outcome)
      switch outcome {
      case .found(let result):
        ScreenshotFeedbackWindow.show(self.publishText(result), near: NSEvent.mouseLocation)
        self.finishInlineAnnotation()
      case .empty:
        ScreenshotFeedbackWindow.show(
          detailed ? "Still no text found" : "No text found - press O again for a detailed read",
          near: NSEvent.mouseLocation
        )
      case .failed:
        ScreenshotFeedbackWindow.dismiss(progress)
        self.present("Text recognition failed. Try a smaller region.")
      }
    }
  }
}
