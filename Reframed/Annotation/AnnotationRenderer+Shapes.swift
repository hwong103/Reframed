import CoreGraphics
import CoreText
import Foundation

extension AnnotationRenderer {
  static func draw(
    _ item: AnnotationItem,
    in context: CGContext,
    viewport: Viewport,
    document: AnnotationDocument
  ) {
    switch item.kind {
    case .arrow:
      drawArrow(item, in: context, viewport: viewport)
    case .rectangle:
      drawRectangle(item, in: context, viewport: viewport)
    case .ellipse:
      drawEllipse(item, in: context, viewport: viewport)
    case .line:
      drawLine(item, in: context, viewport: viewport)
    case .pen:
      drawPolyline(item, width: item.style.strokeWidth, in: context, viewport: viewport)
    case .highlighter:
      drawPolyline(item, width: max(item.style.strokeWidth, 8), in: context, viewport: viewport)
    case .text:
      drawText(item, in: context, viewport: viewport)
    case .blur:
      applyBlur(item, in: context, viewport: viewport, document: document)
    case .pixelate:
      applyPixelate(item, in: context, viewport: viewport, document: document)
    case .crop:
      break
    }
  }

  static func drawLine(_ item: AnnotationItem, in context: CGContext, viewport: Viewport) {
    strokePath(item, lineWidth: item.style.strokeWidth, in: context) { path in
      path.move(to: viewport.point(item.start))
      path.addLine(to: viewport.point(item.end))
    }
  }

  static func drawArrow(_ item: AnnotationItem, in context: CGContext, viewport: Viewport) {
    let headStart = viewport.point(item.start)
    let tip = viewport.point(item.end)
    let width = max(1, item.style.strokeWidth)
    let headLength = max(8, width * 3)
    let angle = atan2(tip.y - headStart.y, tip.x - headStart.x)
    let spread = CGFloat.pi / 7
    let left = CGPoint(x: tip.x - headLength * cos(angle - spread), y: tip.y - headLength * sin(angle - spread))
    let right = CGPoint(x: tip.x - headLength * cos(angle + spread), y: tip.y - headLength * sin(angle + spread))
    strokePath(item, lineWidth: width, in: context) { path in
      path.move(to: headStart)
      path.addLine(to: tip)
      path.move(to: tip)
      path.addLine(to: left)
      path.move(to: tip)
      path.addLine(to: right)
    }
  }

  static func drawRectangle(_ item: AnnotationItem, in context: CGContext, viewport: Viewport) {
    let rect = viewport.rect(item.bounds.standardized)
    context.saveGState()
    context.setAlpha(item.style.opacity)
    if let fill = item.style.fillColor {
      context.setFillColor(cgColor(fill))
      context.fill(rect)
    }
    context.setStrokeColor(cgColor(item.style.strokeColor))
    context.setLineWidth(max(1, item.style.strokeWidth))
    context.setLineJoin(.round)
    context.stroke(rect, width: max(1, item.style.strokeWidth))
    context.restoreGState()
  }

  static func drawEllipse(_ item: AnnotationItem, in context: CGContext, viewport: Viewport) {
    let rect = viewport.rect(item.bounds.standardized)
    context.saveGState()
    context.setAlpha(item.style.opacity)
    if let fill = item.style.fillColor {
      context.setFillColor(cgColor(fill))
      context.fillEllipse(in: rect)
    }
    context.setStrokeColor(cgColor(item.style.strokeColor))
    context.setLineWidth(max(1, item.style.strokeWidth))
    context.strokeEllipse(in: rect)
    context.restoreGState()
  }

  static func drawPolyline(_ item: AnnotationItem, width: CGFloat, in context: CGContext, viewport: Viewport) {
    let points = item.polyline
    guard points.count >= 2 else {
      return
    }
    strokePath(item, lineWidth: max(1, width), in: context) { path in
      path.move(to: viewport.point(points[0]))
      for point in points.dropFirst() {
        path.addLine(to: viewport.point(point))
      }
    }
  }

  static func drawText(_ item: AnnotationItem, in context: CGContext, viewport: Viewport) {
    guard !item.style.text.isEmpty else {
      return
    }
    let font = CTFontCreateWithName("Helvetica" as CFString, item.style.fontSize, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor(item.style.strokeColor),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: item.style.text, attributes: attributes))
    let anchor = viewport.point(item.start)
    context.saveGState()
    context.setAlpha(item.style.opacity)
    context.textPosition = CGPoint(x: anchor.x, y: anchor.y - CTFontGetAscent(font))
    CTLineDraw(line, context)
    context.restoreGState()
  }

  static func strokePath(
    _ item: AnnotationItem,
    lineWidth: CGFloat,
    in context: CGContext,
    build: (CGMutablePath) -> Void
  ) {
    context.saveGState()
    context.setAlpha(item.style.opacity)
    context.setStrokeColor(cgColor(item.style.strokeColor))
    context.setLineWidth(max(1, lineWidth))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let path = CGMutablePath()
    build(path)
    context.addPath(path)
    context.strokePath()
    context.restoreGState()
  }
}
