import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenshotCoordinator {
  private let captureSession: ScreenshotSession
  private let selectionCoordinator = SelectionCoordinator()
  private weak var appState: SessionState?
  private var exclusions: [SCRunningApplication] = []
  private var previousApplication: NSRunningApplication?
  private var isCapturing = false

  init(appState: SessionState?, captureSession: ScreenshotSession = ScreenshotSession()) {
    self.appState = appState
    self.captureSession = captureSession
  }

  func captureRegion() {
    guard admit() else { return }
    previousApplication = NSWorkspace.shared.frontmostApplication
    Task { [weak self] in
      guard let self else { return }
      self.exclusions = await self.resolveExclusions()
      let request = SelectionRequest(
        timerDelay: 0,
        confirmTitle: "Capture",
        hint: "Shift to lock aspect ratio \u{00b7} Esc to cancel \u{00b7} Enter to capture",
        onCountdownStart: {},
        onConfirm: { selection in self.confirmRegion(selection) },
        onCancel: { self.cancel() }
      )
      self.selectionCoordinator.beginSelection(request: request)
    }
  }

  func captureDisplay() {
    guard admit() else { return }
    previousApplication = NSWorkspace.shared.frontmostApplication
    Task { [weak self] in
      guard let self else { return }
      self.exclusions = await self.resolveExclusions()
      await self.finishDisplayCapture()
    }
  }

  func captureWindow() {
    refuse("Window capture is not available yet.")
  }

  func repeatLast() {
    guard admit() else { return }
    previousApplication = NSWorkspace.shared.frontmostApplication
    Task { [weak self] in
      guard let self else { return }
      self.exclusions = await self.resolveExclusions()
      await self.finishRepeatCapture()
    }
  }

  func cancel() {
    selectionCoordinator.destroyAll()
    isCapturing = false
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  var hasLastCapture: Bool {
    captureSession.lastResult != nil
  }

  func saveLastCapture() {
    guard captureSession.lastResult != nil else {
      refuse("There is no screenshot to save yet.")
      return
    }
    do {
      let url = try captureSession.saveLast()
      captureSession.copyLastToClipboard()
      ScreenshotFeedbackWindow.show("Screenshot saved", detail: url.lastPathComponent, near: NSEvent.mouseLocation)
    } catch {
      present(error.localizedDescription)
    }
  }

  private func confirmRegion(_ selection: SelectionRect) {
    selectionCoordinator.destroyAll()
    Task { await finishRegionCapture(selection) }
  }

  private func finishRegionCapture(_ selection: SelectionRect) async {
    defer { isCapturing = false }
    do {
      let result = try await captureSession.capture(selection, excludingApplications: exclusions)
      ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
      ScreenshotFeedbackWindow.show("Copied to clipboard", near: CGPoint(x: selection.rect.midX, y: selection.rect.minY))
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  private func finishDisplayCapture() async {
    defer { isCapturing = false }
    let displayID = NSScreen.displayID(for: NSEvent.mouseLocation)
    do {
      let result = try await captureSession.captureDisplay(displayID, excludingApplications: exclusions)
      ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
      ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  private func finishRepeatCapture() async {
    defer { isCapturing = false }
    do {
      let result = try await captureSession.repeatLastCapture(excludingApplications: exclusions)
      ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
      ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  private func admit() -> Bool {
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
    isCapturing = true
    return true
  }

  private func blockedReason(for state: CaptureState) -> String? {
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

  private func resolveExclusions() async -> [SCRunningApplication] {
    guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
    guard let content = try? await Permissions.fetchShareableContent() else { return [] }
    return content.applications.filter { $0.bundleIdentifier == bundleID }
  }

  private func refuse(_ message: String) {
    let restore = NSWorkspace.shared.frontmostApplication
    present(message)
    restoreFocus(restore)
  }

  private func present(_ message: String) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Screenshot unavailable"
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func restoreFocus(_ application: NSRunningApplication?) {
    guard let application else { return }
    guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
    application.activate()
  }
}
