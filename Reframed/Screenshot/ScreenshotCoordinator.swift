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
  var lastWindowSelection: WindowSetSelection?
  var annotationSavedURL: URL?
  var scrollingSession: ScrollingCaptureSession?
  var scrollingGeneration = 0
  var scrollingRequest = 0

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
      if let selection = self.lastWindowSelection {
        await self.repeatWindowSet(selection)
      } else {
        await self.finishRepeatCapture()
      }
    }
  }

  func cancel() {
    scrollingRequest += 1
    if let session = scrollingSession {
      scrollingSession = nil
      scrollingGeneration = 0
      session.cancel()
    }
    selectionCoordinator.destroyAll()
    windowSelectionCoordinator?.destroyOverlay()
    windowSelectionCoordinator = nil
    isCapturing = false
    isTextSnip = false
    frozenDisplays.removeAll()
    annotationSavedURL = nil
    ScreenshotActionBarWindow.dismiss()
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  func handleEscape() -> Bool {
    if let session = scrollingSession, session.isEscapable {
      session.cancel()
      return true
    }
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
      let copied = captureSession.copyLastToClipboard()
      ScreenshotFeedbackWindow.show(
        copied ? "Screenshot saved" : "Saved, but the clipboard copy failed",
        detail: url.lastPathComponent,
        near: NSEvent.mouseLocation
      )
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
      hint: "Click a window to capture \u{00b7} Shift-click adds windows \u{00b7} Option drops the shadow \u{00b7} Esc to cancel",
      backgroundImages: frozenDisplays,
      initialFullScreen: true,
      hoverTargetsEnabled: true,
      hoverTargets: HoverTargetSnapshot.current(),
      annotation: isTextSnip ? nil : makeAnnotationHandlers(),
      onCountdownStart: {},
      onConfirm: { selection in self.confirmSelection(selection) },
      onConfirmWindows: { windowIDs, includeShadow in self.confirmWindowSet(windowIDs, includeShadow: includeShadow) },
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
      lastWindowSelection = nil
      if ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL) {
        ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
      } else {
        present("Could not copy the screenshot to the clipboard.")
      }
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
      if ImageExporter.copyToPasteboard(outcome.result.image, fileURL: captureSession.lastSavedURL) {
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

}
