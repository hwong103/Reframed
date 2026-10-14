import AppKit
import CoreGraphics

extension AnnotationCanvasView {
  func currentLayout() -> Layout {
    let size = contentSize
    let inset = beautifyInset
    if let explicitLayout {
      return Layout(
        scale: explicitLayout.scale,
        origin: CGPoint(
          x: explicitLayout.origin.x + inset * explicitLayout.scale,
          y: explicitLayout.origin.y + inset * explicitLayout.scale
        )
      )
    }
    if isInline {
      guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
        return Layout(scale: 1, origin: CGPoint(x: bounds.midX, y: bounds.midY))
      }
      let scale = min(bounds.width / size.width, bounds.height / size.height)
      return Layout(
        scale: scale,
        origin: CGPoint(x: bounds.minX + inset * scale, y: bounds.minY + inset * scale)
      )
    }
    let area = bounds.insetBy(dx: 16, dy: 16)
    guard size.width > 0, size.height > 0, area.width > 0, area.height > 0 else {
      return Layout(scale: 1, origin: CGPoint(x: bounds.midX, y: bounds.midY))
    }
    let scale = min(area.width / size.width, area.height / size.height)
    let scaled = CGSize(width: size.width * scale, height: size.height * scale)
    return Layout(
      scale: scale,
      origin: CGPoint(
        x: area.midX - scaled.width / 2 + inset * scale,
        y: area.midY - scaled.height / 2 + inset * scale
      )
    )
  }

  var contentSize: CGSize {
    let inset = beautifyInset
    guard inset > 0 else { return model.outputSize }
    return CGSize(
      width: model.outputSize.width + inset * 2,
      height: model.outputSize.height + inset * 2
    )
  }

  var beautifyInset: CGFloat {
    guard beautifyStyle.isActive else { return 0 }
    let density = max(beautifyScale, 1)
    let padding = (beautifyStyle.padding * density).rounded()
    guard beautifyStyle.shadowOpacity > 0 else { return padding }
    let bleed = ((beautifyStyle.shadowRadius + beautifyStyle.shadowOffset) * density).rounded()
    return padding + bleed
  }

  var displayRect: CGRect {
    let layout = currentLayout()
    let size = model.outputSize
    return CGRect(
      x: layout.origin.x,
      y: layout.origin.y,
      width: size.width * layout.scale,
      height: size.height * layout.scale
    )
  }

  func viewPoint(_ source: CGPoint) -> CGPoint {
    let layout = currentLayout()
    let crop = AnnotationRenderer.cropRect(for: model.document)
    let out = model.outputSize
    return CGPoint(
      x: layout.origin.x + (source.x - (crop?.minX ?? 0)) * layout.scale,
      y: layout.origin.y + (out.height - (source.y - (crop?.minY ?? 0))) * layout.scale
    )
  }

  func sourcePoint(_ view: CGPoint) -> CGPoint {
    let layout = currentLayout()
    guard layout.scale > 0 else { return .zero }
    let crop = AnnotationRenderer.cropRect(for: model.document)
    let out = model.outputSize
    return CGPoint(
      x: (view.x - layout.origin.x) / layout.scale + (crop?.minX ?? 0),
      y: (crop?.minY ?? 0) + out.height - (view.y - layout.origin.y) / layout.scale
    )
  }

  func viewRect(for source: CGRect) -> CGRect {
    let topLeft = viewPoint(CGPoint(x: source.minX, y: source.maxY))
    let bottomRight = viewPoint(CGPoint(x: source.maxX, y: source.minY))
    return CGRect(
      x: topLeft.x,
      y: topLeft.y,
      width: bottomRight.x - topLeft.x,
      height: bottomRight.y - topLeft.y
    )
  }

  func handleCenters(forSource rect: CGRect) -> [CGPoint] {
    let corners = [
      CGPoint(x: rect.minX, y: rect.minY),
      CGPoint(x: rect.midX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.midY),
      CGPoint(x: rect.maxX, y: rect.maxY),
      CGPoint(x: rect.midX, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.midY),
    ]
    return corners.map { viewPoint($0) }
  }

  func drawRenderedImage(in context: CGContext) {
    let layout = currentLayout()
    guard layout.scale > 0 else { return }
    guard beautifyStyle.isActive else {
      drawDocument(in: context, layout: layout)
      return
    }
    let viewScale = max(beautifyScale, 1) * layout.scale
    let frame = displayRect
    let inset = beautifyInset * layout.scale
    AnnotationRenderer.drawBeautifyBackground(
      beautifyStyle.background,
      in: context,
      canvas: frame.insetBy(dx: -inset, dy: -inset)
    )
    let radius = beautifyStyle.cornerRadius * viewScale
    let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if beautifyStyle.shadowOpacity > 0 {
      context.saveGState()
      context.addPath(path)
      context.setFillColor(NSColor.black.withAlphaComponent(1).cgColor)
      context.setShadow(
        offset: CGSize(width: 0, height: -beautifyStyle.shadowOffset * viewScale),
        blur: beautifyStyle.shadowRadius * viewScale,
        color: NSColor.black.withAlphaComponent(beautifyStyle.shadowOpacity).cgColor
      )
      context.fillPath()
      context.restoreGState()
    }
    context.saveGState()
    context.addPath(path)
    context.clip()
    drawDocument(in: context, layout: layout)
    context.restoreGState()
  }

  private func drawDocument(in context: CGContext, layout: Layout) {
    let deviceScale = layout.scale * (window?.backingScaleFactor ?? 1)
    let interpolation: CGInterpolationQuality = deviceScale < 1 ? .high : .none
    context.saveGState()
    context.translateBy(x: layout.origin.x, y: layout.origin.y)
    context.scaleBy(x: layout.scale, y: layout.scale)
    context.clip(to: CGRect(origin: .zero, size: model.outputSize))
    if let composite = dragCompositeImage() {
      context.interpolationQuality = interpolation
      context.draw(composite, in: CGRect(origin: .zero, size: model.outputSize))
    } else {
      AnnotationRenderer.render(
        model.document,
        image: model.image,
        into: context,
        interpolation: interpolation
      )
    }
    context.restoreGState()
  }

  func drawSelection(in context: CGContext) {
    guard let item = model.selectedItem else { return }
    let sourceRect = item.bounds.standardized
    let rect = viewRect(for: sourceRect)
    context.saveGState()
    context.setStrokeColor(NSColor.controlAccentColor.cgColor)
    context.setLineWidth(1)
    context.setLineDash(phase: 0, lengths: [4, 3])
    context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
    context.setLineDash(phase: 0, lengths: [])
    context.setFillColor(NSColor.white.cgColor)
    for center in handleCenters(forSource: sourceRect) {
      let handle = CGRect(
        x: center.x - handleSize / 2,
        y: center.y - handleSize / 2,
        width: handleSize,
        height: handleSize
      )
      context.fill(handle)
      context.stroke(handle)
    }
    context.restoreGState()
  }

  func drawPendingCrop(in context: CGContext) {
    guard let crop = model.pendingCrop else { return }
    let rect = viewRect(for: crop.standardized)
    let display = displayRect
    context.saveGState()
    context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
    for band in cropBands(within: display, excluding: rect) {
      context.fill(band)
    }
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(1.5)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.stroke(rect.intersection(display))
    context.restoreGState()
  }

  func cropBands(within outer: CGRect, excluding inner: CGRect) -> [CGRect] {
    let cut = inner.intersection(outer)
    guard !cut.isNull, !cut.isEmpty else { return [outer] }
    let top = CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: cut.minY - outer.minY)
    let bottom = CGRect(x: outer.minX, y: cut.maxY, width: outer.width, height: outer.maxY - cut.maxY)
    let left = CGRect(x: outer.minX, y: cut.minY, width: cut.minX - outer.minX, height: cut.height)
    let right = CGRect(x: cut.maxX, y: cut.minY, width: outer.maxX - cut.maxX, height: cut.height)
    return [top, bottom, left, right]
  }

  func drawViewportHUD(in context: CGContext) {
    guard explicitLayout != nil, bounds.width > 140, bounds.height > 80 else { return }
    let magnification = currentLayout().scale * (window?.backingScaleFactor ?? 1)
    let text = "\(Int((magnification * 100).rounded()))%"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
      .foregroundColor: NSColor.white,
    ]
    let textSize = (text as NSString).size(withAttributes: attributes)
    let box = CGRect(
      x: bounds.maxX - textSize.width - 22,
      y: bounds.minY + 10,
      width: textSize.width + 12,
      height: textSize.height + 6
    )
    context.saveGState()
    context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
    context.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil))
    context.fillPath()
    (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    context.restoreGState()
  }
}
