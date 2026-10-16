import CoreGraphics

extension CGRect {
  var normalized: CGRect {
    CGRect(
      x: min(origin.x, origin.x + size.width),
      y: min(origin.y, origin.y + size.height),
      width: abs(size.width),
      height: abs(size.height)
    )
  }

  func clamped(to bounds: CGRect) -> CGRect {
    let x = max(bounds.minX, min(origin.x, bounds.maxX - width))
    let y = max(bounds.minY, min(origin.y, bounds.maxY - height))
    let w = min(width, bounds.width)
    let h = min(height, bounds.height)
    return CGRect(x: x, y: y, width: w, height: h)
  }

  func clampedPreservingAspect(to bounds: CGRect) -> CGRect {
    let factor = min(1, min(bounds.width / max(width, 1), bounds.height / max(height, 1)))
    let w = width * factor
    let h = height * factor
    let x = max(bounds.minX, min(origin.x, bounds.maxX - w))
    let y = max(bounds.minY, min(origin.y, bounds.maxY - h))
    return CGRect(x: x, y: y, width: w, height: h)
  }
}
