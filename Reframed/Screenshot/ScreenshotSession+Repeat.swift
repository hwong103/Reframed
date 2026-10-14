import CoreGraphics
import Foundation
import ScreenCaptureKit

struct RepeatCapture {
  let result: ScreenshotResult
  let notice: String?
}

extension ScreenshotSession {
  @discardableResult
  func repeatLastCapture(
    excludingApplications: [SCRunningApplication] = []
  ) async throws -> RepeatCapture {
    guard let previous = lastResult else {
      throw ScreenshotSessionError.noPreviousCapture
    }
    if let windowID = lastWindowID {
      do {
        let window = try await resolveWindow(id: windowID)
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
