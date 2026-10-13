import Foundation

extension SelectionOverlayView {
  func constrainToAspect(
    _ original: CGRect,
    delta: CGPoint,
    aspect: CGFloat,
    handle: ResizeHandle
  ) -> CGRect {
    let ratio = aspect > 0 ? aspect : 1
    let growsRight = handle == .right || handle == .topRight || handle == .bottomRight
    let anchoredRight = handle == .left || handle == .topLeft || handle == .bottomLeft
    let growsUp = handle == .top || handle == .topLeft || handle == .topRight
    let drivenByWidth = growsRight || anchoredRight

    let raw: CGFloat
    if drivenByWidth {
      raw = original.width + (growsRight ? delta.x : -delta.x)
    } else {
      raw = original.width + (growsUp ? delta.y : -delta.y) * ratio
    }

    let minimum: CGFloat = 10
    let width = max(raw, minimum, minimum * ratio)
    let height = width / ratio

    var rect = CGRect(x: original.minX, y: original.minY, width: width, height: height)
    if anchoredRight {
      rect.origin.x = original.maxX - width
    }
    if !growsUp {
      rect.origin.y = original.maxY - height
    }
    return rect
  }
}
