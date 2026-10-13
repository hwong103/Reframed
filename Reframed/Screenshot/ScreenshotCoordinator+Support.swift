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
    annotationSavedURL = nil
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

  func captureTextSnip() {
    guard admit() else { return }
    previousApplication = NSWorkspace.shared.frontmostApplication
    isTextSnip = true
    Task { [weak self] in
      guard let self else { return }
      self.exclusions = await self.resolveExclusions()
      await self.freezeThenSelect()
    }
  }

  func confirmSelection(_ selection: SelectionRect) {
    selectionCoordinator.destroyAll()
    if isTextSnip {
      Task { await finishTextSnip(selection) }
    } else {
      Task { await finishRegionCapture(selection) }
    }
  }

  func copyTextFrom(_ image: CGImage) async -> String {
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try OCRService.recognize(in: image)
      }.value
      return publishText(result)
    } catch {
      return "No text found"
    }
  }

  func pinLastCapture() {
    guard let result = captureSession.lastResult else {
      refuse("There is no screenshot to pin yet.")
      return
    }
    PinnedImageManager.shared.pin(result.image, displayID: result.displayID)
    ScreenshotFeedbackWindow.show("Pinned to screen", near: NSEvent.mouseLocation)
  }

  private func finishTextSnip(_ selection: SelectionRect) async {
    defer {
      isCapturing = false
      isTextSnip = false
      frozenDisplays.removeAll()
    }
    do {
      let result = try await capturedRegion(selection)
      lastWindowSelection = nil
      let image = result.image
      let ocr = try await Task.detached(priority: .userInitiated) {
        try OCRService.recognize(in: image)
      }.value
      ScreenshotFeedbackWindow.show(publishText(ocr), near: NSEvent.mouseLocation)
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  @discardableResult
  private func publishText(_ result: OCRResult) -> String {
    guard !result.text.isEmpty else { return "No text found" }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(result.text, forType: .string)
    return "Copied \(result.characterCount) characters"
  }
}
