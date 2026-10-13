import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenshotCoordinator {
  let captureSession: ScreenshotSession
  private let selectionCoordinator = SelectionCoordinator()
  weak var appState: SessionState?
  var exclusions: [SCRunningApplication] = []
  var previousApplication: NSRunningApplication?
  var isCapturing = false
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
      await self.finishDisplayCapture()
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

  private func confirmRegion(_ selection: SelectionRect) {
    selectionCoordinator.destroyAll()
    Task { await finishRegionCapture(selection) }
  }

  private func freezeThenSelect() async {
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
      hint: "Shift to lock aspect ratio \u{00b7} Esc to cancel \u{00b7} Enter to capture",
      backgroundImages: frozenDisplays,
      onCountdownStart: {},
      onConfirm: { selection in self.confirmRegion(selection) },
      onCancel: { self.cancel() }
    )
    selectionCoordinator.beginSelection(request: request)
  }

  private func finishRegionCapture(_ selection: SelectionRect) async {
    defer {
      isCapturing = false
      frozenDisplays.removeAll()
    }
    do {
      let result = try await capturedRegion(selection)
      ImageExporter.copyToPasteboard(result.image, fileURL: captureSession.lastSavedURL)
      showActionBar(near: selection.rect)
    } catch {
      present(error.localizedDescription)
    }
    restoreFocus(previousApplication)
    previousApplication = nil
  }

  private func capturedRegion(_ selection: SelectionRect) async throws -> ScreenshotResult {
    if let frozen = frozenDisplays[selection.displayID] {
      return try captureSession.captureFrozenRegion(selection, from: frozen)
    }
    return try await captureSession.capture(selection, excludingApplications: exclusions)
  }

  func showActionBar(near rect: CGRect) {
    ScreenshotActionBarWindow.show(
      near: rect,
      onCopy: { [weak self] in self?.captureSession.copyLastToClipboard() },
      onSaveAndCopy: { [weak self] in self?.savedStatus() ?? "" },
      onAnnotate: { [weak self] in self?.openAnnotation() }
    )
  }

  private func openAnnotation() {
    guard let result = captureSession.lastResult else { return }
    let reference = SourceImageReference(
      identifier: "\(result.displayID)-\(result.createdAt.timeIntervalSince1970)",
      pixelWidth: result.image.width,
      pixelHeight: result.image.height
    )
    AnnotationEditorWindowController.present(image: result.image, reference: reference)
  }

  private func savedStatus() -> String {
    do {
      let url = try captureSession.saveLast()
      captureSession.copyLastToClipboard()
      return "Saved \(url.lastPathComponent)"
    } catch {
      return error.localizedDescription
    }
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
