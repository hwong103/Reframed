import CoreGraphics
import Foundation

@MainActor
enum WindowCaptureComposer {
  static let spacingPoints: CGFloat = 32

  static func compose(_ images: [CGImage], scale: CGFloat) -> CGImage? {
    guard let first = images.first else { return nil }
    guard images.count > 1 else { return first }

    let spacing = max(1, Int((spacingPoints * max(scale, 1)).rounded()))
    let contentWidth = images.map(\.width).max() ?? first.width
    let contentHeight = images.reduce(0) { $0 + $1.height } + spacing * (images.count - 1)
    let width = contentWidth + spacing * 2
    let height = contentHeight + spacing * 2

    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }

    context.setFillColor(CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    var top = height - spacing
    for image in images {
      let x = (width - image.width) / 2
      top -= image.height
      context.draw(
        image,
        in: CGRect(x: x, y: top, width: image.width, height: image.height)
      )
      top -= spacing
    }

    return context.makeImage()
  }
}
