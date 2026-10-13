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
    captureSession.adoptRendered(image: image, selection: selection)
    captureSession.copyLastToClipboard()
    ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
  }

  private func annotationSave(_ image: CGImage, _ selection: SelectionRect, copy: Bool) {
    captureSession.adoptRendered(image: image, selection: selection)
    do {
      let url = try captureSession.saveLast()
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
    captureSession.adoptRendered(image: image, selection: selection)
    ScreenshotFeedbackWindow.show(copyTextFromLast(), near: NSEvent.mouseLocation)
  }

  private func annotationPin(_ image: CGImage, _ selection: SelectionRect) {
    captureSession.adoptRendered(image: image, selection: selection)
    PinnedImageManager.shared.pin(image, displayID: selection.displayID)
    ScreenshotFeedbackWindow.show("Pinned to screen", near: NSEvent.mouseLocation)
  }

  private func annotationOpenInWindow(_ image: CGImage, _ selection: SelectionRect) {
    captureSession.adoptRendered(image: image, selection: selection)
    let reference = SourceImageReference(
      identifier: "\(selection.displayID)-\(selection.rect.origin.x)-\(selection.rect.origin.y)",
      pixelWidth: image.width,
      pixelHeight: image.height
    )
    AnnotationEditorWindowController.present(image: image, reference: reference)
  }

  private func annotationPreviewFile(_ image: CGImage, _ selection: SelectionRect) -> URL? {
    captureSession.adoptRendered(image: image, selection: selection)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(ScreenshotNaming.baseName())
      .appendingPathExtension(ScreenshotNaming.fileExtension)
    do {
      try ImageExporter.writePNG(image, to: url)
      return url
    } catch {
      present(error.localizedDescription)
      return nil
    }
  }
}
