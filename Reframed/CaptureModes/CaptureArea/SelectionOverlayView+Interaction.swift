import AppKit

extension SelectionOverlayView {
  var isAutoSelection: Bool {
    isFullDisplayInitial || committedWindowID != nil
  }

  func handleMouseMoved(_ point: CGPoint) {
    mouseLocation = point
    updateCursor()

    if request.hoverTargetsEnabled, !isDragging, !hoverSuppressed, activeHandle == nil,
      handleDragStart == nil
    {
      updateHover(at: point)
    }

    needsDisplay = true
  }

  func handleMouseDown(_ point: CGPoint) {
    if let hosting = controlsHost, !hosting.isHidden {
      let panelPoint = hosting.convert(point, from: self)
      if hosting.bounds.contains(panelPoint) {
        return
      }
    }

    didDrag = false

    if isAutoSelection {
      dragOrigin = point
      isDragging = false
      return
    }

    if let rect = selectionRect {
      for handle in ResizeHandle.allCases {
        let hitArea = handle.rect(for: rect).insetBy(dx: -4, dy: -4)
        if hitArea.contains(point) {
          activeHandle = handle
          handleDragStart = point
          originalRectBeforeResize = rect
          return
        }
      }

      if rect.contains(point) {
        activeHandle = nil
        handleDragStart = point
        originalRectBeforeResize = rect
        NSCursor.closedHand.set()
        return
      }
    }

    dragOrigin = point
    selectionRect = nil
    isDragging = true
    controlsHost?.isHidden = true
    needsDisplay = true
  }

  func handleMouseDragged(_ point: CGPoint, shiftHeld: Bool) {
    if let handle = activeHandle, let start = handleDragStart, let original = originalRectBeforeResize {
      let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
      var newRect = handle.resize(original: original, delta: delta).normalized
      if shiftHeld, original.width > 0, original.height > 0 {
        let aspect = original.width / original.height
        newRect = constrainToAspect(original, delta: delta, aspect: aspect, handle: handle)
      }
      selectionRect = newRect
      needsDisplay = true
      updateControlsPanel()
      return
    }

    if handleDragStart != nil, let original = originalRectBeforeResize {
      let delta = CGPoint(x: point.x - handleDragStart!.x, y: point.y - handleDragStart!.y)
      selectionRect = CGRect(
        x: original.origin.x + delta.x,
        y: original.origin.y + delta.y,
        width: original.width,
        height: original.height
      )
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
    if shiftHeld, w > 0, h > 0 {
      h = w * 9.0 / 16.0
    }
    selectionRect = CGRect(
      x: point.x >= origin.x ? origin.x : origin.x - w,
      y: point.y >= origin.y ? origin.y : origin.y - h,
      width: w,
      height: h
    )
    needsDisplay = true
    updateControlsPanel()
  }

  func handleMouseUp(_ point: CGPoint) {
    if activeHandle != nil || handleDragStart != nil {
      activeHandle = nil
      handleDragStart = nil
      originalRectBeforeResize = nil
      updateControlsPanel()
      return
    }

    if !didDrag, request.hoverTargetsEnabled, isAutoSelection || hoverSuppressed {
      commitHoveredTarget(at: point)
      return
    }

    isDragging = false
    dragOrigin = nil

    if let rect = selectionRect, rect.width < 10 || rect.height < 10 {
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
    }
  }

  func applyFullDisplaySelection() {
    selectionRect = bounds
    isFullDisplayInitial = true
    committedWindowID = nil
    hoverTarget = nil
    needsDisplay = true
    updateControlsPanel()
  }

  private func updateCursor() {
    guard let rect = selectionRect else {
      NSCursor.crosshair.set()
      return
    }

    for handle in ResizeHandle.allCases {
      let hitArea = handle.rect(for: rect).insetBy(dx: -4, dy: -4)
      if hitArea.contains(mouseLocation) {
        handle.cursor.set()
        return
      }
    }

    if rect.contains(mouseLocation) {
      NSCursor.openHand.set()
    } else {
      NSCursor.arrow.set()
    }
  }

}
