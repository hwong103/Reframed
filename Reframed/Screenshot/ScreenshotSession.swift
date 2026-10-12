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

@MainActor
@Observable
final class ScreenshotSession {
  private(set) var lastResult: ScreenshotResult?
  private(set) var lastSelection: SelectionRect?
  private(set) var lastSavedURL: URL?

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
    lastResult = result
    lastSavedURL = nil
    return result
  }

  @discardableResult
  func repeatLastCapture(
    excludingApplications: [SCRunningApplication] = []
  ) async throws -> ScreenshotResult {
    guard let previous = lastResult else {
      throw ScreenshotSessionError.noPreviousCapture
    }
    if let selection = lastSelection {
      return try await capture(selection, excludingApplications: excludingApplications)
    }
    return try await captureDisplay(previous.displayID, excludingApplications: excludingApplications)
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
}
