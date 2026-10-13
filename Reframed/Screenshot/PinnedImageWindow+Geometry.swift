import AppKit
import CoreGraphics

extension PinnedImageWindow {
  func present(near point: CGPoint?) {
    let visible = (NSScreen.screen(for: displayID) ?? NSScreen.main)?.visibleFrame
    let size = Self.fitted(frame.size, into: visible)
    let anchor = point ?? NSEvent.mouseLocation
    let origin = confined(CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2), size, on: visible)
    setFrame(NSRect(origin: origin, size: size), display: false)
    orderFrontRegardless()
    onFrameChange?(pinID)
  }

  func restoreFrame(_ saved: CGRect) {
    let visible = (NSScreen.screen(for: displayID) ?? NSScreen.main)?.visibleFrame
    let size = Self.fitted(saved.size, into: visible)
    let origin = confined(saved.origin, size, on: visible)
    setFrame(NSRect(origin: origin, size: size), display: false)
  }

  func confined(_ origin: CGPoint, _ size: CGSize, on visible: CGRect?) -> CGPoint {
    guard let visible else { return origin }
    return Self.confinedOrigin(origin, size, on: visible)
  }

  static func confinedOrigin(_ origin: CGPoint, _ size: CGSize, on visible: CGRect) -> CGPoint {
    let x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
    let y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
    return CGPoint(x: x, y: y)
  }

  static func fitted(_ size: CGSize, into visible: CGRect?) -> CGSize {
    guard let visible else { return size }
    let ratio = min(1, min(visible.width * 0.9 / max(size.width, 1), visible.height * 0.9 / max(size.height, 1)))
    return CGSize(width: size.width * ratio, height: size.height * ratio)
  }

  func resize(by delta: CGFloat) {
    let visible = (screen ?? NSScreen.screen(for: displayID) ?? NSScreen.main)?.visibleFrame
    let width = min(max(frame.width + delta, Self.minimumSide), maxSide)
    let size = Self.fitted(CGSize(width: width, height: width / aspect), into: visible)
    var newFrame = frame
    newFrame.origin.y += frame.height - size.height
    newFrame.size = size
    newFrame.origin = confined(newFrame.origin, size, on: visible)
    setFrame(newFrame, display: true)
    onFrameChange?(pinID)
  }

  static func naturalSize(for image: CGImage, displayID: CGDirectDisplayID) -> CGSize {
    let scale = NSScreen.screen(for: displayID)?.backingScaleFactor ?? 2
    let width = CGFloat(image.width) / scale
    let height = CGFloat(image.height) / scale
    guard width > 0, height > 0 else { return CGSize(width: minimumSide, height: minimumSide) }
    let floorRatio = max(1, minimumSide / width, minimumSide / height)
    let size = CGSize(width: width * floorRatio, height: height * floorRatio)
    guard let limit = NSScreen.screen(for: displayID)?.visibleFrame else { return size }
    let ratio = min(1, min(limit.width * 0.8 / max(size.width, 1), limit.height * 0.8 / max(size.height, 1)))
    return CGSize(width: size.width * ratio, height: size.height * ratio)
  }
}
