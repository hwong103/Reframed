import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

extension StillCaptureService {
  func captureWindow(_ window: SCWindow) async throws -> ScreenshotResult {
    try assertCapturable(window)
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let geometry = filter.contentRect
    let scale = CGFloat(filter.pointPixelScale)
    guard geometry.width >= 1, geometry.height >= 1, scale > 0 else {
      throw ScreenshotCaptureError.windowUnavailable
    }
    let expected = CGSize(
      width: CGFloat(pixelLength(geometry.width, scale: scale)),
      height: CGFloat(pixelLength(geometry.height, scale: scale))
    )
    let configuration = makeConfiguration()
    configuration.width = Int(expected.width)
    configuration.height = Int(expected.height)
    configuration.scalesToFit = false
    configuration.ignoreShadowsSingleWindow = true
    configuration.shouldBeOpaque = true
    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter,
      configuration: configuration
    )
    try assertRealisedSize(CGSize(width: image.width, height: image.height), expected: expected, window: window)
    return ScreenshotResult(
      image: image,
      displayID: displayID(for: window),
      pointSize: geometry.size,
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

  private func assertRealisedSize(_ realised: CGSize, expected: CGSize, window: SCWindow) throws {
    guard realised.width >= 1, realised.height >= 1 else {
      throw ScreenshotCaptureError.windowUnavailable
    }
    let fits = realised.width <= expected.width && realised.height <= expected.height
    guard fits else {
      throw ScreenshotCaptureError.windowGeometryMismatch(expected: expected, actual: realised)
    }
    if isFullyOnScreen(window), realised != expected {
      throw ScreenshotCaptureError.windowGeometryMismatch(expected: expected, actual: realised)
    }
  }

  private func isFullyOnScreen(_ window: SCWindow) -> Bool {
    let frame = windowFrameInAppKit(window)
    return NSScreen.screens.contains { $0.frame.contains(frame) }
  }

  private func windowFrameInAppKit(_ window: SCWindow) -> CGRect {
    let frame = window.frame
    return CGRect(
      x: frame.origin.x,
      y: NSScreen.primaryScreenHeight - frame.origin.y - frame.height,
      width: frame.width,
      height: frame.height
    )
  }

  private func displayID(for window: SCWindow) -> CGDirectDisplayID {
    let frame = window.frame
    return NSScreen.displayID(for: CGPoint(x: frame.midX, y: frame.midY))
  }
}
