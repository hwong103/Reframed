import AppKit

extension SelectionOverlayView {
  var isAnnotating: Bool {
    annotationSession != nil
  }

  func currentSelection() -> SelectionRect? {
    guard let rect = selectionRect, let window else { return nil }
    let screenRect = window.convertToScreen(convert(rect, to: nil))
    let anchor = CGPoint(x: screenRect.midX, y: screenRect.midY)
    let displayID = NSScreen.screens.first { $0.frame.contains(anchor) }?.displayID ?? CGMainDisplayID()
    return SelectionRect(rect: screenRect, displayID: displayID)
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

  func updateAnnotationLayout() {
    guard let session = annotationSession, let rect = selectionRect, let selection = currentSelection() else {
      return
    }
    session.update(bounds: bounds, localRect: rect, selection: selection)
  }

  func handleAnnotationKey(_ event: NSEvent) -> Bool {
    annotationSession?.handleKey(event) ?? false
  }

  func annotationHitTest(_ point: NSPoint) -> NSView? {
    guard let session = annotationSession else { return nil }
    for host in [session.closeHost, session.toolbarHost, session.badgeHost] where host.superview != nil {
      let local = host.convert(point, from: self)
      if host.bounds.contains(local) {
        return host
      }
    }
    return nil
  }
}
