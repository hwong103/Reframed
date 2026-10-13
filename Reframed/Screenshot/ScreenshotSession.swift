import AppKit
import CoreGraphics
import Foundation
import Observation
import ScreenCaptureKit

enum ScreenshotSessionError: LocalizedError {
  case noPreviousCapture

  var errorDescription: String? {
    "There is no screenshot to repeat yet"
  }
}

struct RepeatCapture {
  let result: ScreenshotResult
  let notice: String?
}

@MainActor
@Observable
final class ScreenshotSession {
  private(set) var lastResult: ScreenshotResult?
  private(set) var lastSelection: SelectionRect?
  private(set) var lastSavedURL: URL?
  private(set) var lastWindowID: CGWindowID?

  private let service: StillCaptureService

  init(service: StillCaptureService = StillCaptureService()) {
    self.service = service
  }

  @discardableResult
  func capture(
    _ selection: SelectionRect,
    excludingApplications: [SCRunningApplication] = []
  ) async throws -> ScreenshotResult {
    let result = try await service.capture(selection, excludingApplications: excludingApplications)
    lastSelection = selection
    lastWindowID = nil
    lastResult = result
    lastSavedURL = nil
    return result
  }

  @discardableResult
  func captureDisplay(
    _ displayID: CGDirectDisplayID,
    excludingApplications: [SCRunningApplication] = []
  ) async throws -> ScreenshotResult {
    let result = try await service.captureDisplay(displayID, excludingApplications: excludingApplications)
    lastSelection = nil
    lastWindowID = nil
    lastResult = result
    lastSavedURL = nil
    return result
  }

  @discardableResult
  func captureWindow(
    _ window: SCWindow,
    includeShadow: Bool = true,
    excludingApplications: [SCRunningApplication] = []
  ) async throws -> ScreenshotResult {
    let result = try await service.captureWindow(window, includeShadow: includeShadow)
    lastSelection = nil
    lastWindowID = window.windowID
    lastResult = result
    lastSavedURL = nil
    return result
  }

  func resolveWindow(id: CGWindowID) async throws -> SCWindow {
    try await service.resolveWindow(id: id)
  }

  func windowImage(_ window: SCWindow, includeShadow: Bool) async throws -> ScreenshotResult {
    try await service.captureWindow(window, includeShadow: includeShadow)
  }

  @discardableResult
  func adoptComposedWindow(image: CGImage, displayID: CGDirectDisplayID, scale: CGFloat) -> ScreenshotResult {
    let result = ScreenshotResult(
      image: image,
      displayID: displayID,
      pointSize: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale),
      backingScale: scale
    )
    lastSelection = nil
    lastWindowID = nil
    lastResult = result
    lastSavedURL = nil
    return result
  }

  @discardableResult
  func repeatLastCapture(
    excludingApplications: [SCRunningApplication] = []
  ) async throws -> RepeatCapture {
    guard let previous = lastResult else {
      throw ScreenshotSessionError.noPreviousCapture
    }
    if let windowID = lastWindowID {
      do {
        let window = try await service.resolveWindow(id: windowID)
        let result = try await captureWindow(window, excludingApplications: excludingApplications)
        return RepeatCapture(result: result, notice: nil)
      } catch {
        return try await repeatFallback(previous, excludingApplications: excludingApplications)
      }
    }
    if let selection = lastSelection {
      return RepeatCapture(
        result: try await capture(selection, excludingApplications: excludingApplications),
        notice: nil
      )
    }
    return RepeatCapture(
      result: try await captureDisplay(previous.displayID, excludingApplications: excludingApplications),
      notice: nil
    )
  }

  func freezeScreens(
    excludingApplications: [SCRunningApplication] = []
  ) async throws -> [CGDirectDisplayID: CGImage] {
    try await service.captureScreens(excludingApplications: excludingApplications)
  }

  @discardableResult
  func captureFrozenRegion(_ selection: SelectionRect, from image: CGImage) throws -> ScreenshotResult {
    let result = try service.crop(selection, from: image)
    lastSelection = selection
    lastWindowID = nil
    lastResult = result
    lastSavedURL = nil
    return result
  }

  @discardableResult
  func adoptRendered(image: CGImage, selection: SelectionRect) -> ScreenshotResult {
    let result = ScreenshotResult(
      image: image,
      displayID: selection.displayID,
      pointSize: selection.rect.size,
      backingScale: selection.backingScaleFactor
    )
    if selection.isScreenRegion {
      lastSelection = selection
      lastWindowID = nil
    }
    lastResult = result
    lastSavedURL = nil
    return result
  }

  @discardableResult
  func copyLastToClipboard() -> Bool {
    guard let result = lastResult else { return false }
    ImageExporter.copyToPasteboard(result.image, fileURL: lastSavedURL)
    return true
  }

  @discardableResult
  func saveLast() throws -> URL {
    guard let result = lastResult else {
      throw ScreenshotSessionError.noPreviousCapture
    }
    let url = ScreenshotNaming.destinationURL(date: result.createdAt)
    try ImageExporter.writePNG(result.image, to: url)
    lastSavedURL = url
    return url
  }

  private func repeatFallback(
    _ previous: ScreenshotResult,
    excludingApplications: [SCRunningApplication]
  ) async throws -> RepeatCapture {
    if let selection = lastSelection {
      return RepeatCapture(
        result: try await capture(selection, excludingApplications: excludingApplications),
        notice: "The previous window is unavailable; captured the last region instead."
      )
    }
    return RepeatCapture(
      result: try await captureDisplay(previous.displayID, excludingApplications: excludingApplications),
      notice: "The previous window is unavailable; captured the display instead."
    )
  }
}
