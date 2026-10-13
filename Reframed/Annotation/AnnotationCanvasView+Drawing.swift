import AppKit
import CoreGraphics

extension AnnotationCanvasView {
  func currentLayout() -> Layout {
    if let explicitLayout {
      return explicitLayout
    }
    let size = model.outputSize
    if isInline {
      guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
        return Layout(scale: 1, origin: CGPoint(x: bounds.midX, y: bounds.midY))
      }
      let scale = min(bounds.width / size.width, bounds.height / size.height)
      return Layout(scale: scale, origin: CGPoint(x: bounds.minX, y: bounds.minY))
    }
    let inset = bounds.insetBy(dx: 16, dy: 16)
    guard size.width > 0, size.height > 0, inset.width > 0, inset.height > 0 else {
      return Layout(scale: 1, origin: CGPoint(x: bounds.midX, y: bounds.midY))
    }
    let scale = min(inset.width / size.width, inset.height / size.height)
    let scaled = CGSize(width: size.width * scale, height: size.height * scale)
    return Layout(
      scale: scale,
      origin: CGPoint(x: inset.midX - scaled.width / 2, y: inset.midY - scaled.height / 2)
    )
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
    context.saveGState()
    context.translateBy(x: layout.origin.x, y: layout.origin.y)
    context.scaleBy(x: layout.scale, y: layout.scale)
    context.clip(to: CGRect(origin: .zero, size: model.outputSize))
    AnnotationRenderer.render(model.document, image: model.image, into: context)
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
    let text = "\(Int((currentLayout().scale * 100).rounded()))%"
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

  static func viewportFitScale(viewportWidth: CGFloat, imageWidth: CGFloat) -> CGFloat {
    guard viewportWidth > 0, imageWidth > 0 else { return 1 }
    return min(1, viewportWidth / imageWidth)
  }

  static func clampedViewportOrigin(_ origin: CGPoint, content: CGSize, viewport: CGRect) -> CGPoint {
    CGPoint(
      x: clampedViewportAxis(origin.x, content: content.width, lower: viewport.minX, upper: viewport.maxX),
      y: clampedViewportAxis(origin.y, content: content.height, lower: viewport.minY, upper: viewport.maxY)
    )
  }

  private static func clampedViewportAxis(
    _ value: CGFloat,
    content: CGFloat,
    lower: CGFloat,
    upper: CGFloat
  ) -> CGFloat {
    let span = upper - lower
    guard span > 0, content > 0 else { return lower }
    if content <= span {
      return lower + (span - content) / 2
    }
    return min(max(value, upper - content), lower)
  }
}
