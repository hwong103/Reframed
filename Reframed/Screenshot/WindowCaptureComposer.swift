import CoreGraphics
import Foundation

@MainActor
enum WindowCaptureComposer {
  static let spacingPoints: CGFloat = 32
  static let pixelBudget = 200_000_000

  static func compose(_ images: [CGImage], scale: CGFloat) -> CGImage? {
    guard let first = images.first else { return nil }
    guard images.count > 1 else { return first }

    let spacing = max(1, Int((spacingPoints * max(scale, 1)).rounded()))
    let contentWidth = images.map(\.width).max() ?? first.width
    var contentHeight = 0
    for image in images {
      guard let sum = adding(contentHeight, image.height) else { return nil }
      contentHeight = sum
    }
    guard let gapTotal = multiplying(spacing, images.count - 1),
      let margin = multiplying(spacing, 2),
      let stackedHeight = adding(contentHeight, gapTotal),
      let height = adding(stackedHeight, margin),
      let width = adding(contentWidth, margin),
      width >= 1,
      height >= 1,
      let area = multiplying(width, height),
      area <= pixelBudget
    else {
      return nil
    }

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

  private static func adding(_ lhs: Int, _ rhs: Int) -> Int? {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? nil : sum
  }

  private static func multiplying(_ lhs: Int, _ rhs: Int) -> Int? {
    let (product, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    return overflow ? nil : product
  }
}
