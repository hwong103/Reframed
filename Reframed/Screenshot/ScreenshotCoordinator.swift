import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenshotCoordinator {
  let captureSession: ScreenshotSession
  let selectionCoordinator = SelectionCoordinator()
  weak var appState: SessionState?
  var exclusions: [SCRunningApplication] = []
  var previousApplication: NSRunningApplication?
  var isCapturing = false
  var isTextSnip = false
  var frozenDisplays: [CGDirectDisplayID: CGImage] = [:]
  var windowSelectionCoordinator: WindowSelectionCoordinator?

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
      await self.freezeThenSelect()
    }
  }

  func captureDisplay() {
    guard admit() else { return }
    previousApplication = NSWorkspace.shared.frontmostApplication
    Task { [weak self] in
      guard let self else { return }
      self.exclusions = await self.resolveExclusions()
      await self.freezeThenSelect()
    }
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
    windowSelectionCoordinator?.destroyOverlay()
    windowSelectionCoordinator = nil
    isCapturing = false
    isTextSnip = false
    frozenDisplays.removeAll()
    ScreenshotActionBarWindow.dismiss()
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  func handleEscape() -> Bool {
    guard ScreenshotActionBarWindow.isVisible else { return false }
    ScreenshotActionBarWindow.dismiss()
    return true
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

  func freezeThenSelect() async {
    do {
      frozenDisplays = try await captureSession.freezeScreens(excludingApplications: exclusions)
    } catch {
      isCapturing = false
      present(error.localizedDescription)
      restoreFocus(previousApplication)
      previousApplication = nil
      return
    }
    let request = SelectionRequest(
      timerDelay: 0,
      confirmTitle: "Capture",
      hint: "Move to highlight \u{00b7} Shift to lock aspect ratio \u{00b7} Esc to cancel \u{00b7} Enter to capture",
      backgroundImages: frozenDisplays,
      initialFullScreen: true,
      hoverTargetsEnabled: true,
      annotation: isTextSnip ? nil : makeAnnotationHandlers(),
      onCountdownStart: {},
      onConfirm: { selection in self.confirmSelection(selection) },
      onConfirmWindow: { windowID, rect in self.confirmWindowTarget(windowID, rect: rect) },
      onCancel: { self.cancel() }
    )
    selectionCoordinator.beginSelection(request: request)
  }

  func finishRegionCapture(_ selection: SelectionRect) async {
    defer {
      isCapturing = false
      frozenDisplays.removeAll()
    }
    do {
      let result = try await capturedRegion(selection)
      ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
      ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  func capturedRegion(_ selection: SelectionRect) async throws -> ScreenshotResult {
    if let frozen = frozenDisplays[selection.displayID] {
      return try captureSession.captureFrozenRegion(selection, from: frozen)
    }
    return try await captureSession.capture(selection, excludingApplications: exclusions)
  }

  private func finishRepeatCapture() async {
    defer { isCapturing = false }
    do {
      let outcome = try await captureSession.repeatLastCapture(excludingApplications: exclusions)
      ImageExporter.copyToPasteboard(outcome.result.image, fileURL: captureSession.lastSavedURL)
      ScreenshotFeedbackWindow.show(outcome.notice ?? "Copied to clipboard", near: NSEvent.mouseLocation)
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

}
