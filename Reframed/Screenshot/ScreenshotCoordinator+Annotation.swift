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
      scrollingCapture: { [weak self] selection in self?.startScrollingCapture(selection) },
      finish: { [weak self] in self?.finishInlineAnnotation() },
      finishWithoutRefocus: { [weak self] in self?.finishInlineAnnotation(refocus: false) },
      cancel: { [weak self] in self?.cancel() }
    )
  }

  func finishInlineAnnotation(refocus: Bool = true) {
    teardownInlineAnnotation(refocus: refocus)
  }

  private func teardownInlineAnnotation(refocus: Bool) {
    scrollingRequest += 1
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
    if captureSession.copyLastToClipboard() {
      ScreenshotFeedbackWindow.show(
        "Copied to clipboard",
        detail: "\(image.width) \u{00d7} \(image.height) px",
        near: NSEvent.mouseLocation
      )
    } else {
      present("Could not copy the screenshot to the clipboard.")
    }
  }

  private func annotationSave(_ image: CGImage, _ selection: SelectionRect, copy: Bool) {
    adoptAnnotationRegion(image, selection)
    do {
      let url = try captureSession.saveLast()
      annotationSavedURL = url
      let copied = !copy || captureSession.copyLastToClipboard()
      ScreenshotFeedbackWindow.show(
        copy && !copied ? "Saved, but the clipboard copy failed" : (copy ? "Saved and copied" : "Screenshot saved"),
        detail: "\(image.width) \u{00d7} \(image.height) px - \(url.lastPathComponent)",
        near: NSEvent.mouseLocation
      )
    } catch {
      present(error.localizedDescription)
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

  func adoptAnnotationRegion(_ image: CGImage, _ selection: SelectionRect) {
    scrollingRequest += 1
    if selection.isScreenRegion {
      lastWindowSelection = nil
    }
    captureSession.adoptRendered(image: image, selection: selection)
  }

  func startScrollingCapture(_ selection: SelectionRect) {
    guard scrollingSession == nil else { return }
    guard selection.isScreenRegion, selection.rect.width >= 40, selection.rect.height >= 40 else {
      ScreenshotFeedbackWindow.show("Scrolling capture needs a screen region", near: NSEvent.mouseLocation)
      return
    }
    scrollingRequest += 1
    let request = scrollingRequest
    Task { [weak self] in
      guard let self else { return }
      if self.exclusions.isEmpty {
        self.exclusions = await self.resolveExclusions()
      }
      guard self.scrollingRequest == request, self.scrollingSession == nil else { return }
      self.beginScrollingCapture(selection)
    }
  }

  private func beginScrollingCapture(_ selection: SelectionRect) {
    guard scrollingSession == nil else { return }
    selectionCoordinator.destroyAll()
    windowSelectionCoordinator?.destroyOverlay()
    windowSelectionCoordinator = nil
    frozenDisplays.removeAll()
    annotationSavedURL = nil
    let session = ScrollingCaptureSession(
      selection: selection,
      captureSession: captureSession,
      exclusions: exclusions
    )
    session.connect(
      onFinish: { [weak self, weak session] outcome in
        guard
          let self, let session, self.scrollingSession === session,
          self.scrollingGeneration == session.generation
        else { return }
        self.finishScrollingCapture(outcome, selection: selection)
      },
      onCancel: { [weak self, weak session] in
        guard let self, let session, self.scrollingSession === session else { return }
        self.cancelScrollingCapture()
      }
    )
    scrollingSession = session
    scrollingGeneration = session.generation
    session.start()
  }

  private func finishScrollingCapture(_ outcome: ScrollStitcher.StitchOutcome, selection: SelectionRect) {
    scrollingSession = nil
    scrollingGeneration = 0
    guard let image = outcome.image else {
      isCapturing = false
      present(outcome.message)
      restoreFocus(previousApplication)
      previousApplication = nil
      return
    }
    lastWindowSelection = nil
    captureSession.adoptRendered(image: image, selection: selection)
    if outcome.termination != .userFinish || outcome.droppedDuplicates > 0 {
      ScreenshotFeedbackWindow.show(outcome.message, near: NSEvent.mouseLocation)
    }
    selectionCoordinator.presentComposedAnnotation(
      image: image,
      displayID: selection.displayID,
      handlers: makeAnnotationHandlers(),
      onCancel: { [weak self] in self?.cancel() }
    )
  }

  private func cancelScrollingCapture() {
    guard scrollingSession != nil else { return }
    scrollingSession = nil
    scrollingGeneration = 0
    cancel()
  }
}
