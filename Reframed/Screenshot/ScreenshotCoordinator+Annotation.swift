import AppKit
import CoreGraphics

extension ScreenshotCoordinator {
  func makeAnnotationHandlers() -> SelectionAnnotationHandlers {
    SelectionAnnotationHandlers(
      copy: { [weak self] image, selection in self?.annotationCopy(image, selection) },
      save: { [weak self] image, selection in self?.annotationSave(image, selection, copy: false) },
      saveAndCopy: { [weak self] image, selection in self?.annotationSave(image, selection, copy: true) },
      captureText: { [weak self] image, selection in self?.annotationCaptureText(image, selection) },
      pin: { [weak self] image, selection in self?.annotationPin(image, selection) },
      openInWindow: { [weak self] image, selection in self?.annotationOpenInWindow(image, selection) },
      openInPreview: { [weak self] image, selection in self?.annotationPreviewFile(image, selection) },
      finish: { [weak self] in self?.finishInlineAnnotation() },
      finishWithoutRefocus: { [weak self] in self?.finishInlineAnnotation(refocus: false) },
      cancel: { [weak self] in self?.cancel() }
    )
  }

  func finishInlineAnnotation(refocus: Bool = true) {
    teardownInlineAnnotation(refocus: refocus)
  }

  private func teardownInlineAnnotation(refocus: Bool) {
    selectionCoordinator.destroyAll()
    windowSelectionCoordinator?.destroyOverlay()
    windowSelectionCoordinator = nil
    isCapturing = false
    isTextSnip = false
    frozenDisplays.removeAll()
    if refocus {
      restoreFocus(previousApplication)
    }
    previousApplication = nil
  }

  private func annotationCopy(_ image: CGImage, _ selection: SelectionRect) {
    adoptAnnotationRegion(image, selection)
    captureSession.copyLastToClipboard()
    ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
  }

  private func annotationSave(_ image: CGImage, _ selection: SelectionRect, copy: Bool) {
    adoptAnnotationRegion(image, selection)
    do {
      let url = try captureSession.saveLast()
      annotationSavedURL = url
      if copy {
        captureSession.copyLastToClipboard()
      }
      ScreenshotFeedbackWindow.show(
        copy ? "Saved and copied" : "Screenshot saved",
        detail: url.lastPathComponent,
        near: NSEvent.mouseLocation
      )
    } catch {
      present(error.localizedDescription)
    }
  }

  private func annotationCaptureText(_ image: CGImage, _ selection: SelectionRect) {
    adoptAnnotationRegion(image, selection)
    ScreenshotFeedbackWindow.show("Reading text...", near: NSEvent.mouseLocation)
    Task { @MainActor [weak self] in
      guard let self else { return }
      let message = await self.copyTextFrom(image)
      ScreenshotFeedbackWindow.show(message, near: NSEvent.mouseLocation)
      guard self.isCapturing else { return }
      self.finishInlineAnnotation()
    }
  }

  private func annotationPin(_ image: CGImage, _ selection: SelectionRect) {
    adoptAnnotationRegion(image, selection)
    PinnedImageManager.shared.pin(image, displayID: selection.displayID)
    ScreenshotFeedbackWindow.show("Pinned to screen", near: NSEvent.mouseLocation)
  }

  private func annotationOpenInWindow(_ image: CGImage, _ selection: SelectionRect) {
    adoptAnnotationRegion(image, selection)
    let reference = SourceImageReference(
      identifier: "\(selection.displayID)-\(selection.rect.origin.x)-\(selection.rect.origin.y)",
      pixelWidth: image.width,
      pixelHeight: image.height
    )
    AnnotationEditorWindowController.present(image: image, reference: reference)
  }

  private func annotationPreviewFile(_ image: CGImage, _ selection: SelectionRect) -> URL? {
    adoptAnnotationRegion(image, selection)
    if let saved = annotationSavedURL, FileManager.default.fileExists(atPath: saved.path) {
      return saved
    }
    do {
      let url = try captureSession.saveLast()
      annotationSavedURL = url
      return url
    } catch {
      present(error.localizedDescription)
      return nil
    }
  }

  private func adoptAnnotationRegion(_ image: CGImage, _ selection: SelectionRect) {
    if selection.isScreenRegion {
      lastWindowSelection = nil
    }
    captureSession.adoptRendered(image: image, selection: selection)
  }
}
