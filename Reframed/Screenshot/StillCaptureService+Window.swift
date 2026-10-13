import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

extension StillCaptureService {
  static let windowShadowPadding: CGFloat = 32

  func captureWindow(_ window: SCWindow, includeShadow: Bool = true) async throws -> ScreenshotResult {
    try assertCapturable(window)
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let geometry = filter.contentRect
    let scale = CGFloat(filter.pointPixelScale)
    guard geometry.width >= 1, geometry.height >= 1, scale > 0 else {
      throw ScreenshotCaptureError.windowUnavailable
    }
    let contentPixels = CGSize(
      width: CGFloat(pixelLength(geometry.width, scale: scale)),
      height: CGFloat(pixelLength(geometry.height, scale: scale))
    )
    let configuration = makeConfiguration()
    configuration.width = Int(contentPixels.width)
    configuration.height = Int(contentPixels.height)
    configuration.scalesToFit = false
    configuration.ignoreShadowsSingleWindow = !includeShadow
    configuration.shouldBeOpaque = !includeShadow
    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter,
      configuration: configuration
    )
    let realised = CGSize(width: image.width, height: image.height)
    try assertRealisedSize(realised, contentPixels: contentPixels, includeShadow: includeShadow, window: window)
    return ScreenshotResult(
      image: image,
      displayID: Self.displayID(for: window),
      pointSize: CGSize(width: realised.width / scale, height: realised.height / scale),
      backingScale: scale
    )
  }

  func resolveWindow(id: CGWindowID) async throws -> SCWindow {
    let content = try await Permissions.fetchShareableContent()
    guard let window = content.windows.first(where: { $0.windowID == id }) else {
      throw ScreenshotCaptureError.windowUnavailable
    }
    try assertCapturable(window)
    return window
  }

  func assertCapturable(_ window: SCWindow) throws {
    if let bundleID = Bundle.main.bundleIdentifier,
      window.owningApplication?.bundleIdentifier == bundleID
    {
      throw ScreenshotCaptureError.ownWindow
    }
    guard window.isOnScreen else {
      throw ScreenshotCaptureError.windowOffScreen
    }
  }

  static func frozenWindowSelection(for window: SCWindow, includeShadow: Bool) -> SelectionRect? {
    let displayID = displayID(for: window)
    guard NSScreen.screen(for: displayID) != nil else { return nil }
    let frame = windowFrameInAppKit(window)
    guard frame.width >= 1, frame.height >= 1 else { return nil }
    let padding = includeShadow ? windowShadowPadding : 0
    return SelectionRect(rect: frame.insetBy(dx: -padding, dy: -padding), displayID: displayID)
  }

  private func assertRealisedSize(
    _ realised: CGSize,
    contentPixels: CGSize,
    includeShadow: Bool,
    window: SCWindow
  ) throws {
    guard realised.width >= 1, realised.height >= 1 else {
      throw ScreenshotCaptureError.windowUnavailable
    }

    if includeShadow {
      let lostContent =
        realised.width < contentPixels.width - 2 || realised.height < contentPixels.height - 2
      let implausible =
        realised.width > contentPixels.width * 2 + 2 || realised.height > contentPixels.height * 2 + 2
      guard !lostContent, !implausible else {
        throw ScreenshotCaptureError.windowGeometryMismatch(expected: contentPixels, actual: realised)
      }
      return
    }

    let matches = realised == contentPixels
    let clipped =
      !isFullyOnScreen(window)
      && realised.width <= contentPixels.width
      && realised.height <= contentPixels.height
    guard matches || clipped else {
      throw ScreenshotCaptureError.windowGeometryMismatch(expected: contentPixels, actual: realised)
    }
  }

  private func isFullyOnScreen(_ window: SCWindow) -> Bool {
    let frame = Self.windowFrameInAppKit(window)
    return NSScreen.screens.contains { $0.frame.contains(frame) }
  }

  private static func windowFrameInAppKit(_ window: SCWindow) -> CGRect {
    let frame = window.frame
    return CGRect(
      x: frame.origin.x,
      y: NSScreen.primaryScreenHeight - frame.origin.y - frame.height,
      width: frame.width,
      height: frame.height
    )
  }

  private static func displayID(for window: SCWindow) -> CGDirectDisplayID {
    let frame = window.frame
    return NSScreen.displayID(for: CGPoint(x: frame.midX, y: frame.midY))
  }
}
