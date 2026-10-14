import AppKit
import CoreGraphics

extension InlineAnnotationSession {
  func copy() {
    apply(handlers.copy)
    end()
  }

  func save() {
    apply(handlers.save)
    end()
  }

  func saveAndCopy() {
    apply(handlers.saveAndCopy)
    end()
  }

  func makeDragItem() -> NSPasteboardItem? {
    guard let image = renderedSelection() else { return nil }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReframedDrag", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = ScreenshotNaming.uniqueURL(
      in: directory,
      baseName: ScreenshotNaming.baseName(),
      fileExtension: "png"
    )
    let item = NSPasteboardItem()
    var published = false
    if (try? ImageExporter.writePNG(image, to: url)) != nil {
      published = item.setString(url.absoluteString, forType: .fileURL) || published
    }
    if let png = try? ImageExporter.pngData(from: image) {
      published = item.setData(png, forType: .png) || published
    }
    if let tiff = ImageExporter.tiffData(from: image) {
      published = item.setData(tiff, forType: .tiff) || published
    }
    return published ? item : nil
  }
  func pin() {
    apply(handlers.pin)
    end()
  }

  func openInWindow() {
    apply(handlers.openInWindow)
    end(restoringFocus: false)
  }

  func openInPreview() {
    let url = renderedSelection().flatMap { handlers.openInPreview($0, selection) }
    end(restoringFocus: false)
    guard let url else { return }
    Task { @MainActor in
      openInPreviewApplication(url)
    }
  }

  func scrollingCapture() { handlers.scrollingCapture(selection) }

  private func openInPreviewApplication(_ url: URL) {
    let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
    guard FileManager.default.fileExists(atPath: preview.path) else {
      NSWorkspace.shared.open(url)
      return
    }
    NSWorkspace.shared.open(
      [url],
      withApplicationAt: preview,
      configuration: NSWorkspace.OpenConfiguration()
    ) { _, _ in }
  }

  func undo() {
    model.undo()
    finishEditing()
  }

  func redo() {
    model.redo()
    finishEditing()
  }

  func deleteSelected() {
    guard model.selectionID != nil else { return }
    canvas.deleteSelection()
    refreshState()
    canvas.needsDisplay = true
  }

  private func finishEditing() {
    refreshState()
    canvas.needsDisplay = true
  }

  private func apply(_ action: (CGImage, SelectionRect) -> Void) {
    if let rendered = renderedSelection() {
      action(rendered, selection)
    }
  }

  func end(restoringFocus: Bool = true) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      restoringFocus ? self.handlers.finish() : self.handlers.finishWithoutRefocus()
    }
  }

  func makeActions() -> CaptureAnnotationToolbarActions {
    CaptureAnnotationToolbarActions(
      undo: { [weak self] in self?.undo() },
      redo: { [weak self] in self?.redo() },
      deleteSelected: { [weak self] in self?.deleteSelected() },
      copy: { [weak self] in self?.copy() },
      save: { [weak self] in self?.save() },
      saveAndCopy: { [weak self] in self?.saveAndCopy() },
      captureText: { [weak self] in self?.captureText() },
      beautify: { [weak self] in self?.toggleBeautify() },
      pin: { [weak self] in self?.pin() },
      openInWindow: { [weak self] in self?.openInWindow() },
      openInPreview: { [weak self] in self?.openInPreview() },
      scrollingCapture: { [weak self] in self?.scrollingCapture() },
      makeDragItem: { [weak self] in self?.makeDragItem() },
      cancel: { [weak self] in self?.cancel() },
      selectTool: { [weak self] tool in self?.selectTool(tool) },
      applyStyle: { [weak self] in self?.applyStyle() }
    )
  }

  func makeCloseAction() -> () -> Void {
    { [weak self] in
      Task { @MainActor in
        self?.cancel()
      }
    }
  }

  func layoutBadge(badgeSize: CGSize, bounds: CGRect) {
    guard badgeSize.width > 0 else { return }
    var origin = CGPoint(x: localRect.minX, y: localRect.maxY - badgeSize.height / 2)
    origin.x = clamp(origin.x, min: bounds.minX + 8, max: bounds.maxX - badgeSize.width - 8)
    origin.y = clamp(origin.y, min: bounds.minY + 8, max: bounds.maxY - badgeSize.height - 8)
    badgeHost.frame = NSRect(origin: origin, size: badgeSize)
    badgeHost.needsDisplay = true
  }

  func layoutClose(bounds: CGRect) {
    let size = closeHost.fittingSize
    guard size.width > 0 else { return }
    var origin = CGPoint(x: localRect.maxX + 6, y: localRect.maxY - size.height / 2)
    origin.x = clamp(origin.x, min: bounds.minX + 6, max: bounds.maxX - size.width - 6)
    origin.y = clamp(origin.y, min: bounds.minY + 6, max: bounds.maxY - size.height - 6)
    closeHost.frame = NSRect(origin: origin, size: size)
    closeHost.needsDisplay = true
  }

  func layoutToolbar(bounds: CGRect) {
    let size = toolbarHost.fittingSize
    guard size.width > 0 else { return }
    let gap: CGFloat = 18
    var origin = CGPoint(x: localRect.midX - size.width / 2, y: localRect.minY - size.height - gap)
    if origin.y < bounds.minY + 8 {
      origin.y = localRect.minY + 12
    }
    origin.x = clamp(origin.x, min: bounds.minX + 8, max: bounds.maxX - size.width - 8)
    origin.y = clamp(origin.y, min: bounds.minY + 8, max: bounds.maxY - size.height - 8)
    toolbarHost.frame = NSRect(origin: origin, size: size)
    toolbarHost.needsDisplay = true
  }

  func renderedSelection() -> CGImage? {
    guard let full = model.renderedImage() else { return nil }
    let scale = selection.backingScaleFactor > 0 ? selection.backingScaleFactor : 1
    let points = selection.stillCaptureRect
    let pixelRect = CGRect(
      x: points.minX * scale,
      y: points.minY * scale,
      width: points.width * scale,
      height: points.height * scale
    ).integral
    let imageBounds = CGRect(x: 0, y: 0, width: full.width, height: full.height)
    let cropped = pixelRect.intersection(imageBounds)
    guard cropped.width >= 1, cropped.height >= 1 else { return nil }
    guard let region = full.cropping(to: cropped) else { return nil }
    return AnnotationRenderer.beautified(region, style: canvas.beautifyStyle, scale: scale)
  }

  private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
    guard upper > lower else { return lower }
    return Swift.min(Swift.max(value, lower), upper)
  }
}
