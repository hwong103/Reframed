import AppKit

extension SelectionOverlayView {
  func drawOverlay(context: CGContext) {
    let holes = selectionHoles()
    if let backgroundImage {
      context.draw(backgroundImage, in: bounds)
      drawDimOverlay(context: context, holes: holes)
    } else {
      context.setFillColor(ReframedColors.overlayBackground.cgColor)
      context.fill(bounds)
      if !holes.isEmpty {
        context.setBlendMode(.clear)
        for hole in holes {
          context.fill(hole)
        }
        context.setBlendMode(.normal)
      }
    }

    drawWindowHighlights(context: context)

    if let rect = selectionRect {
      if annotationSession != nil {
        return
      }
      context.setStrokeColor(ReframedColors.selectionBorder.cgColor)
      context.setLineWidth(1.0)
      context.setLineDash(phase: 0, lengths: [5, 4])
      context.stroke(rect)

      drawGrid(context: context, rect: rect)
      drawCircularHandles(context: context, rect: rect)
    } else {
      if annotationSession != nil {
        return
      }
      let crossColor = ReframedColors.crosshair
      context.setStrokeColor(crossColor.cgColor)
      context.setLineWidth(0.5)
      context.setLineDash(phase: 0, lengths: [])

      context.move(to: CGPoint(x: bounds.minX, y: mouseLocation.y))
      context.addLine(to: CGPoint(x: bounds.maxX, y: mouseLocation.y))
      context.strokePath()

      context.move(to: CGPoint(x: mouseLocation.x, y: bounds.minY))
      context.addLine(to: CGPoint(x: mouseLocation.x, y: bounds.maxY))
      context.strokePath()
    }
  }

  func drawDimOverlay(context: CGContext, holes: [CGRect]) {
    let path = CGMutablePath()
    path.addRect(bounds)
    for hole in holes {
      path.addRect(hole)
    }
    context.saveGState()
    context.addPath(path)
    context.setFillColor(ReframedColors.overlayBackground.cgColor)
    context.fillPath(using: .evenOdd)
    context.restoreGState()
  }

  func selectionHoles() -> [CGRect] {
    guard annotationSession?.isResizable ?? true else { return [] }
    var rects: [CGRect] = []
    if let rect = selectionRect {
      rects.append(rect)
    }
    for rect in selectedWindowRects.values where !rects.contains(rect) {
      rects.append(rect)
    }
    return rects
  }

  func drawWindowHighlights(context: CGContext) {
    guard !selectedWindowRects.isEmpty else { return }
    context.setLineDash(phase: 0, lengths: [])
    for rect in selectedWindowRects.values {
      context.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
      context.fill(rect)
      context.setStrokeColor(NSColor.controlAccentColor.cgColor)
      context.setLineWidth(2)
      context.stroke(rect.insetBy(dx: -1, dy: -1))
    }
  }

  func drawGrid(context: CGContext, rect: CGRect) {
    let gridColor = ReframedColors.selectionGrid
    context.setStrokeColor(gridColor.cgColor)
    context.setLineWidth(0.5)
    context.setLineDash(phase: 0, lengths: [4, 4])

    let thirdW = rect.width / 3
    for i in 1...2 {
      let x = rect.minX + thirdW * CGFloat(i)
      context.move(to: CGPoint(x: x, y: rect.minY))
      context.addLine(to: CGPoint(x: x, y: rect.maxY))
      context.strokePath()
    }

    let thirdH = rect.height / 3
    for i in 1...2 {
      let y = rect.minY + thirdH * CGFloat(i)
      context.move(to: CGPoint(x: rect.minX, y: y))
      context.addLine(to: CGPoint(x: rect.maxX, y: y))
      context.strokePath()
    }

    let centerColor = ReframedColors.selectionCenter
    context.setStrokeColor(centerColor.cgColor)
    context.setLineWidth(0.5)
    context.setLineDash(phase: 0, lengths: [6, 3])

    let cx = rect.midX
    let cy = rect.midY

    context.move(to: CGPoint(x: cx, y: rect.minY))
    context.addLine(to: CGPoint(x: cx, y: rect.maxY))
    context.strokePath()

    context.move(to: CGPoint(x: rect.minX, y: cy))
    context.addLine(to: CGPoint(x: rect.maxX, y: cy))
    context.strokePath()
  }

  func drawCircularHandles(context: CGContext, rect: CGRect) {
    context.setLineDash(phase: 0, lengths: [])

    for handle in ResizeHandle.allCases {
      let handleRect = handle.rect(for: rect)
      let insetRect = handleRect.insetBy(dx: 1, dy: 1)

      context.setFillColor(ReframedColors.handleFill.cgColor)
      context.fillEllipse(in: insetRect)

      context.setStrokeColor(ReframedColors.handleStroke.cgColor)
      context.setLineWidth(1.5)
      context.strokeEllipse(in: insetRect)
    }
  }

  func annotationHitTest(_ point: NSPoint) -> NSView? {
    guard let session = annotationSession else { return nil }
    let editor = session.canvas.textScrollView
    if session.canvas.pendingText != nil, !editor.isHidden, editor.window != nil {
      let local = editor.convert(point, from: self)
      if editor.bounds.contains(local) {
        return editor
      }
    }
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
