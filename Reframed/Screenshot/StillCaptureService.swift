import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenshotCaptureError: LocalizedError {
  case displayNotFound(CGDirectDisplayID)
  case emptySelection

  var errorDescription: String? {
    switch self {
    case .displayNotFound(let displayID):
      return "Could not resolve the display \(displayID) for the screenshot"
    case .emptySelection:
      return "The screenshot selection is empty"
    }
  }
}

@MainActor
struct StillCaptureService {
  func capture(
    _ selection: SelectionRect,
    excludingApplications: [SCRunningApplication] = []
  ) async throws -> ScreenshotResult {
    let sourceRect = selection.stillCaptureRect
    guard sourceRect.width >= 1, sourceRect.height >= 1 else {
      throw ScreenshotCaptureError.emptySelection
    }
    let screen = try resolveScreen(selection.displayID)
    let display = try await resolveDisplay(selection.displayID)
    let scale = screen.backingScaleFactor
    let filter = SCContentFilter(
      display: display,
      excludingApplications: excludingApplications,
      exceptingWindows: []
    )
    let configuration = makeConfiguration()
    configuration.sourceRect = sourceRect
    configuration.width = pixelLength(sourceRect.width, scale: scale)
    configuration.height = pixelLength(sourceRect.height, scale: scale)
    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter,
      configuration: configuration
    )
    return ScreenshotResult(
      image: image,
      displayID: selection.displayID,
      pointSize: sourceRect.size,
      backingScale: scale
    )
  }

  func captureDisplay(
    _ displayID: CGDirectDisplayID,
    excludingApplications: [SCRunningApplication] = []
  ) async throws -> ScreenshotResult {
    let screen = try resolveScreen(displayID)
    let display = try await resolveDisplay(displayID)
    let scale = screen.backingScaleFactor
    let pointSize = screen.frame.size
    let filter = SCContentFilter(
      display: display,
      excludingApplications: excludingApplications,
      exceptingWindows: []
    )
    let configuration = makeConfiguration()
    configuration.width = pixelLength(pointSize.width, scale: scale)
    configuration.height = pixelLength(pointSize.height, scale: scale)
    let image = try await SCScreenshotManager.captureImage(
      contentFilter: filter,
      configuration: configuration
    )
    return ScreenshotResult(
      image: image,
      displayID: displayID,
      pointSize: pointSize,
      backingScale: scale
    )
  }

  private func resolveScreen(_ displayID: CGDirectDisplayID) throws -> NSScreen {
    guard let screen = NSScreen.screen(for: displayID) else {
      throw ScreenshotCaptureError.displayNotFound(displayID)
    }
    return screen
  }

  private func resolveDisplay(_ displayID: CGDirectDisplayID) async throws -> SCDisplay {
    let content = try await Permissions.fetchShareableContent()
    guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
      throw ScreenshotCaptureError.displayNotFound(displayID)
    }
    return display
  }

  private func makeConfiguration() -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    configuration.colorSpaceName = CGColorSpace.sRGB as CFString
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = false
    configuration.capturesAudio = false
    configuration.scalesToFit = false
    configuration.queueDepth = 1
    return configuration
  }

  private func pixelLength(_ points: CGFloat, scale: CGFloat) -> Int {
    max(1, Int((points * scale).rounded()))
  }
}
