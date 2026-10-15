import CoreGraphics

extension AnnotationCanvasView {
  func refreshBounds(_ item: inout AnnotationItem) {
    guard let first = item.points.first else { return }
    var minX = first.x
    var minY = first.y
    var maxX = first.x
    var maxY = first.y
    for point in item.points {
      minX = min(minX, point.x)
      minY = min(minY, point.y)
      maxX = max(maxX, point.x)
      maxY = max(maxY, point.y)
    }
    item.start = CGPoint(x: minX, y: minY)
    item.end = CGPoint(x: maxX, y: maxY)
  }

  func isDegenerate(_ item: AnnotationItem) -> Bool {
    switch item.kind {
    case .pen, .highlighter:
      return item.points.count < 2
    case .arrow, .rectangle, .ellipse, .line, .text, .blur, .pixelate, .crop:
      return item.bounds.width < 1 && item.bounds.height < 1
    }
  }

  func resized(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
    var minX = rect.minX
    var minY = rect.minY
    var maxX = rect.maxX
    var maxY = rect.maxY
    switch handle {
    case .topLeft:
      minX = point.x
      minY = point.y
    case .top:
      minY = point.y
    case .topRight:
      maxX = point.x
      minY = point.y
    case .right:
      maxX = point.x
    case .bottomRight:
      maxX = point.x
      maxY = point.y
    case .bottom:
      maxY = point.y
    case .bottomLeft:
      minX = point.x
      maxY = point.y
    case .left:
      minX = point.x
    }
    return CGRect(
      x: min(minX, maxX),
      y: min(minY, maxY),
      width: abs(maxX - minX),
      height: abs(maxY - minY)
    )
  }

  func transformed(_ item: AnnotationItem, from source: CGRect, to target: CGRect) -> AnnotationItem {
    let scaleX = source.width > 0 ? target.width / source.width : 1
    let scaleY = source.height > 0 ? target.height / source.height : 1
    var result = item
    result.start = mapPoint(item.start, from: source, to: target, scaleX: scaleX, scaleY: scaleY)
    result.end = mapPoint(item.end, from: source, to: target, scaleX: scaleX, scaleY: scaleY)
    result.points = item.points.map { mapPoint($0, from: source, to: target, scaleX: scaleX, scaleY: scaleY) }
    return result
  }

  func fittedText(_ item: AnnotationItem) -> AnnotationItem {
    guard item.kind == .text else { return item }
    let box = item.bounds.standardized
    let width = max(box.width, 1)
    let size = AnnotationTextLayout.boxSize(
      text: item.style.text,
      fontSize: item.style.fontSize,
      width: width
    )
    var result = item
    result.start = CGPoint(x: box.minX, y: box.minY)
    result.end = CGPoint(x: box.minX + width, y: box.minY + size.height)
    return result
  }

  func mapPoint(
    _ point: CGPoint,
    from source: CGRect,
    to target: CGRect,
    scaleX: CGFloat,
    scaleY: CGFloat
  ) -> CGPoint {
    return CGPoint(x: target.minX + (point.x - source.minX) * scaleX, y: target.minY + (point.y - source.minY) * scaleY)
  }

  func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  func constrainedPoint(_ start: CGPoint, _ point: CGPoint, kind: AnnotationToolKind) -> CGPoint {
    let dx = point.x - start.x
    let dy = point.y - start.y
    switch kind {
    case .rectangle, .ellipse, .pixelate:
      let side = max(abs(dx), abs(dy))
      return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    case .line, .arrow:
      let length = hypot(dx, dy)
      guard length > 1 else { return point }
      let step = CGFloat.pi / 4
      let angle = (atan2(dy, dx) / step).rounded() * step
      return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    default:
      return point
    }
  }

  func handleHit(at view: CGPoint) -> Handle? {
    guard let item = model.selectedItem else { return nil }
    let centers = handleCenters(forSource: item.bounds.standardized)
    for (index, center) in centers.enumerated() {
      if hypot(center.x - view.x, center.y - view.y) <= handleHitRadius {
        return Handle(rawValue: index)
      }
    }
    return nil
  }

  func topItem(at source: CGPoint) -> AnnotationItem? {
    for item in model.document.items.reversed() {
      if item.kind == .crop { continue }
      if contains(item: item, point: source) {
        return item
      }
    }
    return nil
  }

  func contains(item: AnnotationItem, point: CGPoint) -> Bool {
    let tolerance = self.tolerance / max(currentLayout().scale, 0.0001)
    switch item.kind {
    case .pen, .highlighter:
      return distanceToPolyline(item.polyline, point) <= tolerance
    case .rectangle, .ellipse:
      return distanceToRectBorder(item.bounds.standardized, point) <= tolerance
    case .arrow, .line:
      guard item.bounds.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
      return distanceToSegment(item.start, item.end, point) <= tolerance + item.style.strokeWidth / 2
    case .text, .blur, .pixelate:
      return item.bounds.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    case .crop:
      return false
    }
  }

  func distanceToPolyline(_ points: [CGPoint], _ point: CGPoint) -> CGFloat {
    guard points.count >= 2 else {
      return points.first.map { hypot($0.x - point.x, $0.y - point.y) } ?? .greatestFiniteMagnitude
    }
    var best = CGFloat.greatestFiniteMagnitude
    for index in 1..<points.count {
      best = min(best, distanceToSegment(points[index - 1], points[index], point))
    }
    return best
  }

  func distanceToRectBorder(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
    let corners = [
      CGPoint(x: rect.minX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.maxY),
    ]
    var best = CGFloat.greatestFiniteMagnitude
    for index in 0..<corners.count {
      best = min(best, distanceToSegment(corners[index], corners[(index + 1) % corners.count], point))
    }
    return best
  }

  func distanceToSegment(_ a: CGPoint, _ b: CGPoint, _ point: CGPoint) -> CGFloat {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else {
      return hypot(point.x - a.x, point.y - a.y)
    }
    let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
    let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
    return hypot(point.x - projection.x, point.y - projection.y)
  }
}
