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

    let fit = min(bounds.width / pixel.width, bounds.height / pixel.height)
    let fitted = CGSize(width: pixel.width * fit, height: pixel.height * fit)
    let localRect = CGRect(
      x: bounds.midX - fitted.width / 2,
      y: bounds.midY - fitted.height / 2,
      width: fitted.width,
      height: fitted.height
    )
    let selection = SelectionRect(
      rect: CGRect(origin: .zero, size: pixel),
      displayID: displayID,
      displayOrigin: .zero,
      displayHeight: pixel.height,
      scale: 1
    )

    selectionRect = localRect
    isFullDisplayInitial = false
    committedWindowID = nil
    hoverTarget = nil
    clearWindowSelection()
    controlsHost?.isHidden = true

    let session = InlineAnnotationSession(
      image: image,
      selection: selection,
      localRect: localRect,
      displaySize: bounds.size,
      handlers: handlers,
      isResizable: false
    )
    annotationSession = session
    session.install(in: self)
    session.state.pointSize = pixel
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
    let selection = session.isResizable ? currentSelection() : nil
    session.update(bounds: bounds, localRect: rect, selection: selection ?? session.selection)
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

  func updateCursor() {
    guard let rect = selectionRect else {
      NSCursor.crosshair.set()
      return
    }

    for handle in ResizeHandle.allCases {
      let hitArea = handle.rect(for: rect).insetBy(dx: -4, dy: -4)
      if hitArea.contains(mouseLocation), annotationSession?.isResizable ?? true {
        handle.cursor.set()
        return
      }
    }

    if rect.contains(mouseLocation) {
      if request.annotation != nil, !(annotationSession?.isSelectionToolActive ?? false) {
        NSCursor.crosshair.set()
      } else {
        NSCursor.openHand.set()
      }
    } else {
      NSCursor.arrow.set()
    }
  }
}
