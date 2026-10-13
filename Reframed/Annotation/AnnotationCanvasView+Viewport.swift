import CoreGraphics

extension AnnotationCanvasView {
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
