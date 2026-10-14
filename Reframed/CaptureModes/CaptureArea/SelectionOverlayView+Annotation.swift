import AppKit

extension SelectionOverlayView {
  var isAnnotating: Bool {
    annotationSession != nil
  }

  var overlayDisplayID: CGDirectDisplayID {
    window?.screen?.displayID ?? CGMainDisplayID()
  }

  func currentSelection() -> SelectionRect? {
    guard let rect = selectionRect, let window else { return nil }
    let screenRect = window.convertToScreen(convert(rect, to: nil))
    return SelectionRect(rect: screenRect, displayID: overlayDisplayID)
  }

  func enterAnnotationMode() {
    guard
      annotationSession == nil,
      let handlers = request.annotation,
      let image = backgroundImage,
      let rect = selectionRect,
      rect.width >= 10,
      rect.height >= 10,
      let selection = currentSelection()
    else {
      request.onCancel()
      return
    }

    isFullDisplayInitial = false
    committedWindowID = nil
    hoverTarget = nil
    controlsHost?.isHidden = true

    let session = InlineAnnotationSession(
      image: image,
      selection: selection,
      localRect: rect,
      displaySize: bounds.size,
      handlers: handlers
    )
    annotationSession = session
    session.install(in: self)
    updateAnnotationLayout()
    window?.makeFirstResponder(self)
    needsDisplay = true
  }

  func enterComposedAnnotation(image: CGImage, displayID: CGDirectDisplayID) {
    guard annotationSession == nil, let handlers = request.annotation else { return }
    let pixel = CGSize(width: image.width, height: image.height)
    guard pixel.width >= 1, pixel.height >= 1 else { return }

    let selection = SelectionRect(
      rect: CGRect(origin: .zero, size: pixel),
      displayID: displayID,
      displayOrigin: .zero,
      displayHeight: pixel.height,
      scale: 1
    )

    selectionRect = bounds
    isFullDisplayInitial = false
    committedWindowID = nil
    hoverTarget = nil
    clearWindowSelection()
    controlsHost?.isHidden = true
    composedViewport = ComposedViewport()

    let session = InlineAnnotationSession(
      image: image,
      selection: selection,
      localRect: bounds,
      displaySize: bounds.size,
      handlers: handlers,
      isResizable: false
    )
    session.onBeautifyChange = { [weak self] in self?.resetComposedViewport() }
    annotationSession = session
    session.install(in: self)
    updateAnnotationLayout()
    window?.makeFirstResponder(self)
    needsDisplay = true
  }

  func confirmAnnotationSelection() {
    if let onConfirmWindows = request.onConfirmWindows, !selectedWindowIDs.isEmpty {
      let windowIDs = selectedWindowIDs
      clearWindowSelection()
      onConfirmWindows(windowIDs, !NSEvent.modifierFlags.contains(.option))
      return
    }

    if let onConfirmWindows = request.onConfirmWindows, let windowID = committedWindowID {
      onConfirmWindows([windowID], !NSEvent.modifierFlags.contains(.option))
      return
    }

    enterAnnotationMode()
  }

  func updateAnnotationLayout() {
    guard let session = annotationSession, let rect = selectionRect else {
      return
    }
    guard session.isResizable else {
      layoutComposedAnnotation(session: session)
      return
    }
    session.update(bounds: bounds, localRect: rect, selection: currentSelection() ?? session.selection)
  }

  func handleAnnotationKey(_ event: NSEvent) -> Bool {
    if handleViewportKey(event) { return true }
    return annotationSession?.handleKey(event) ?? false
  }

  func layoutComposedAnnotation(session: InlineAnnotationSession) {
    let margin: CGFloat = 24
    let inset = bounds.insetBy(dx: margin, dy: margin)
    composedViewport.rect = inset.width >= 2 && inset.height >= 2 ? inset : bounds
    if !composedViewport.isReady {
      composedViewport.scale = AnnotationCanvasView.viewportFitScale(
        viewport: composedViewport.rect.size,
        content: session.canvas.contentSize
      )
      composedViewport.isReady = true
      composedViewport.origin = topAlignedComposedOrigin(session: session)
    }
    let backing = window?.backingScaleFactor ?? 2
    let rect = composedViewport.rect
    let snapped = CGRect(
      origin: CGPoint(
        x: (rect.minX * backing).rounded() / backing,
        y: (rect.minY * backing).rounded() / backing
      ),
      size: rect.size
    )
    composedViewport.rect = snapped
    selectionRect = snapped
    session.localRect = snapped
    session.state.pointSize = session.model.pixelSize
    session.state.dimensionUnit = "px"
    session.clip.frame = snapped
    session.clip.layer?.contentsScale = backing
    session.canvas.frame = CGRect(origin: .zero, size: snapped.size)
    session.canvas.syncContentsScale()
    session.chrome.isHidden = true
    applyComposedViewportOrigin(session: session)
    session.layoutBadge(badgeSize: session.badgeHost.fittingSize, bounds: bounds)
    session.layoutClose(bounds: bounds)
    session.layoutToolbar(bounds: bounds)
  }

  func applyComposedViewportOrigin(session: InlineAnnotationSession) {
    let pixel = session.canvas.contentSize
    let content = CGSize(
      width: pixel.width * composedViewport.scale,
      height: pixel.height * composedViewport.scale
    )
    composedViewport.origin = AnnotationCanvasView.clampedViewportOrigin(
      composedViewport.origin,
      content: content,
      viewport: composedViewport.rect
    )
    session.canvas.explicitLayout = AnnotationCanvasView.Layout(
      scale: composedViewport.scale,
      origin: CGPoint(
        x: composedViewport.origin.x - composedViewport.rect.minX,
        y: composedViewport.origin.y - composedViewport.rect.minY
      )
    )
    session.canvas.needsDisplay = true
  }

  func topAlignedComposedOrigin(session: InlineAnnotationSession) -> CGPoint {
    let pixel = session.canvas.contentSize
    return CGPoint(
      x: composedViewport.rect.midX - pixel.width * composedViewport.scale / 2,
      y: composedViewport.rect.maxY - pixel.height * composedViewport.scale
    )
  }

  func resetComposedViewport() {
    guard let session = annotationSession, !session.isResizable else { return }
    composedViewport.scale = AnnotationCanvasView.viewportFitScale(
      viewport: composedViewport.rect.size,
      content: session.canvas.contentSize
    )
    composedViewport.origin = topAlignedComposedOrigin(session: session)
    applyComposedViewportOrigin(session: session)
  }
}
