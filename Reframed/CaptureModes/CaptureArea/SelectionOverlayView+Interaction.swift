import AppKit

extension SelectionOverlayView {
  func handleMouseMoved(_ point: CGPoint) {
    mouseLocation = point
    if annotationHitTest(point) != nil {
      NSCursor.arrow.set()
      return
    }
    updateCursor()

    if annotationSession != nil {
      needsDisplay = true
      return
    }

    if request.hoverTargetsEnabled, !isDragging, !hoverSuppressed, activeHandle == nil,
      handleDragStart == nil
    {
      updateHover(at: point)
    }

    needsDisplay = true
  }

  func handleMouseDown(_ point: CGPoint, shiftHeld: Bool) {
    annotationSession?.endTextEditing()

    if let hosting = controlsHost, !hosting.isHidden {
      let panelPoint = hosting.convert(point, from: self)
      if hosting.bounds.contains(panelPoint) {
        return
      }
    }

    didDrag = false

    if shiftHeld, isWindowPickEnabled, isAutoSelection {
      handledShiftClick = true
      toggleWindowSelection(at: point)
      return
    }

    if isAutoSelection {
      dragOrigin = point
      isDragging = false
      return
    }

    if annotationSession?.isResizable ?? true, let rect = selectionRect {
      for handle in ResizeHandle.allCases {
        let hitArea = handle.rect(for: rect).insetBy(dx: -4, dy: -4)
        if hitArea.contains(point) {
          activeHandle = handle
          handleDragStart = point
          originalRectBeforeResize = rect
          return
        }
      }

      if let session = annotationSession, !session.isSelectionToolActive {
        handleDragStart = point
        originalRectBeforeResize = rect
        NSCursor.closedHand.set()
        return
      }

      if rect.contains(point) {
        activeHandle = nil
        handleDragStart = point
        originalRectBeforeResize = rect
        NSCursor.closedHand.set()
        return
      }
    }

    if annotationSession != nil {
      return
    }

    dragOrigin = point
    selectionRect = nil
    isDragging = true
    controlsHost?.isHidden = true
    needsDisplay = true
  }

  func handleMouseDragged(_ point: CGPoint, shiftHeld: Bool) {
    let shift = shiftHeld || (annotationSession?.isAspectLocked ?? false)
    if let handle = activeHandle, let start = handleDragStart, let original = originalRectBeforeResize {
      let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
      let locked = shift && original.width > 0 && original.height > 0
      var newRect = handle.resize(original: original, delta: delta).normalized
      if locked {
        let aspect = original.width / original.height
        newRect = constrainToAspect(original, delta: delta, aspect: aspect, handle: handle)
      }
      selectionRect = confined(newRect.normalized, aspect: locked)
      needsDisplay = true
      updateControlsPanel()
      return
    }

    if handleDragStart != nil, let original = originalRectBeforeResize {
      let delta = CGPoint(x: point.x - handleDragStart!.x, y: point.y - handleDragStart!.y)
      let moved = CGRect(
        x: original.origin.x + delta.x,
        y: original.origin.y + delta.y,
        width: original.width,
        height: original.height
      )
      selectionRect = confined(moved)
      needsDisplay = true
      updateControlsPanel()
      return
    }

    guard let origin = dragOrigin else { return }
    didDrag = true
    isDragging = true
    isFullDisplayInitial = false
    committedWindowID = nil
    hoverTarget = nil
    let w = abs(point.x - origin.x)
    var h = abs(point.y - origin.y)
    if shift, w > 0, h > 0 {
      h = w * 9.0 / 16.0
    }
    let drawn = CGRect(
      x: point.x >= origin.x ? origin.x : origin.x - w,
      y: point.y >= origin.y ? origin.y : origin.y - h,
      width: w,
      height: h
    )
    selectionRect = confined(drawn.normalized)
    needsDisplay = true
    updateControlsPanel()
  }

  private func confined(_ rect: CGRect, aspect: Bool = false) -> CGRect {
    guard backgroundImage != nil else { return rect }
    return aspect ? rect.clampedPreservingAspect(to: bounds) : rect.clamped(to: bounds)
  }

  func handleMouseUp(_ point: CGPoint) {
    if handledShiftClick {
      handledShiftClick = false
      isDragging = false
      dragOrigin = nil
      return
    }

    if activeHandle != nil || handleDragStart != nil {
      activeHandle = nil
      handleDragStart = nil
      originalRectBeforeResize = nil
      updateControlsPanel()
      return
    }

    if !didDrag, isWindowPickEnabled, isAutoSelection || hoverSuppressed {
      captureHoveredWindow(at: point)
      return
    }

    isDragging = false
    dragOrigin = nil

    if let rect = selectionRect, rect.width < 10 || rect.height < 10 {
      if request.annotation != nil, annotationSession == nil {
        commitHoveredTarget(at: point)
        captureImmediately()
        return
      }
      if request.initialFullScreen {
        applyFullDisplaySelection()
      } else {
        selectionRect = nil
        controlsHost?.isHidden = true
        needsDisplay = true
      }
    } else if selectionRect != nil {
      if didDrag, request.hoverTargetsEnabled {
        hoverSuppressed = true
      }
      updateControlsPanel()
      captureImmediately()
      return
    }

    if request.annotation != nil, annotationSession == nil {
      applyFullDisplaySelection()
      captureImmediately()
    }
  }

  func captureImmediately() {
    guard request.annotation != nil, annotationSession == nil else { return }
    confirmSelection()
  }
}
