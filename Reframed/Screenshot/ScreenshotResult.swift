import CoreGraphics
import Foundation

@MainActor
struct ScreenshotResult {
  let image: CGImage
  let displayID: CGDirectDisplayID
  let pointSize: CGSize
  let backingScale: CGFloat
  let createdAt: Date

  init(
    image: CGImage,
    displayID: CGDirectDisplayID,
    pointSize: CGSize,
    backingScale: CGFloat,
    createdAt: Date = Date()
  ) {
    self.image = image
    self.displayID = displayID
    self.pointSize = pointSize
    self.backingScale = backingScale
    self.createdAt = createdAt
  }

  var pixelSize: CGSize {
    CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
  }
}
