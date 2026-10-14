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

  func finishRepeatCapture() async {
    defer { isCapturing = false }
    do {
      let outcome = try await captureSession.repeatLastCapture(excludingApplications: exclusions)
      if ImageExporter.copyToPasteboard(outcome.result.image, fileURL: captureSession.lastSavedURL) {
        RecentCaptureStore.shared.record(image: outcome.result.image, filename: ScreenshotNaming.previewName())
        ScreenshotFeedbackWindow.show(outcome.notice ?? "Copied to clipboard", near: NSEvent.mouseLocation)
      } else {
        present("Could not copy the screenshot to the clipboard.")
      }
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  func confirmSelection(_ selection: SelectionRect) {
    selectionCoordinator.destroyAll()
    if isTextSnip {
      let request = scrollingRequest
      Task { await finishTextSnip(selection, request: request) }
    } else {
      Task { await finishRegionCapture(selection) }
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

  private func finishTextSnip(_ selection: SelectionRect, request: Int) async {
    guard scrollingRequest == request else { return }
    let progress = ScreenshotFeedbackWindow.show("Reading text...", near: NSEvent.mouseLocation, sticky: true)
    textProgressToken = progress
    var owned = true
    defer {
      if owned {
        isCapturing = false
        isTextSnip = false
        frozenDisplays.removeAll()
      }
      if textProgressToken == progress {
        textProgressToken = nil
      }
      ScreenshotFeedbackWindow.dismiss(progress)
    }
    do {
      let result = try await frameRegion(selection)
      guard scrollingRequest == request else {
        owned = false
        return
      }
      captureSession.adoptRendered(image: result.image, selection: selection)
      lastWindowSelection = nil
      let image = result.image
      let ocr = try await Task.detached(priority: .userInitiated) {
        try OCRService.recognize(in: image)
      }.value
      guard scrollingRequest == request else {
        owned = false
        return
      }
      ScreenshotFeedbackWindow.show(publishText(ocr), near: NSEvent.mouseLocation)
    } catch {
      guard scrollingRequest == request else {
        owned = false
        return
      }
      present(error.localizedDescription)
    }
    guard owned else { return }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  @discardableResult
  func publishText(_ result: OCRResult) -> String {
    guard !result.text.isEmpty else { return "No text found" }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(result.text, forType: .string)
    return "Copied \(result.characterCount) characters"
  }
}
