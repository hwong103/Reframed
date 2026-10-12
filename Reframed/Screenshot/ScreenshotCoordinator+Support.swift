import AppKit
import Foundation
import ScreenCaptureKit

extension ScreenshotCoordinator {
  func admit() -> Bool {
    guard !isCapturing else { return false }
    guard Permissions.hasScreenRecordingPermission else {
      Permissions.requestScreenRecordingPermission()
      refuse("Screen Recording permission is required to take screenshots.")
      return false
    }
    if let state = appState?.state, let reason = blockedReason(for: state) {
      refuse(reason)
      return false
    }
    ScreenshotActionBarWindow.dismiss()
    isCapturing = true
    return true
  }

  func blockedReason(for state: CaptureState) -> String? {
    switch state {
    case .idle:
      return nil
    case .selecting:
      return "Finish the current selection before taking a screenshot."
    case .countdown:
      return "A recording countdown is running."
    case .recording:
      return "A recording is in progress."
    case .paused:
      return "A recording is paused."
    case .processing:
      return "A recording is being processed."
    case .editing:
      return "Close the editor before taking a screenshot."
    }
  }

  func resolveExclusions() async -> [SCRunningApplication] {
    guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
    guard let content = try? await Permissions.fetchShareableContent() else { return [] }
    return content.applications.filter { $0.bundleIdentifier == bundleID }
  }

  func refuse(_ message: String) {
    let restore = NSWorkspace.shared.frontmostApplication
    present(message)
    restoreFocus(restore)
  }

  func present(_ message: String) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Screenshot unavailable"
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  func restoreFocus(_ application: NSRunningApplication?) {
    guard let application else { return }
    guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
    application.activate()
  }
}
