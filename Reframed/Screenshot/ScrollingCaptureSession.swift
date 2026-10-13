import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class ScrollingCaptureSession {
  struct Limits {
    var maxFrames = 120
    var maxDuration: Duration = .seconds(60)
    var maxSourcePixels = 120_000_000
    var interval: Duration = .milliseconds(200)
    var maxConsecutiveFailures = 3
  }

  private(set) var frameCount = 0
  private(set) var isRunning = false

  private let selection: SelectionRect
  private let captureSession: ScreenshotSession
  private let exclusions: [SCRunningApplication]
  private let limits: Limits
  private let onFinish: (ScrollStitcher.StitchOutcome) -> Void
  private let onCancel: () -> Void

  private var frames: [CGImage] = []
  private var profiles: [ScrollStitcher.FrameProfile] = []
  private var sourcePixels = 0
  private var task: Task<Void, Never>?
  private var hud: ScrollingCaptureHUDWindow?

  init(
    selection: SelectionRect,
    captureSession: ScreenshotSession,
    exclusions: [SCRunningApplication],
    limits: Limits = Limits(),
    onFinish: @escaping (ScrollStitcher.StitchOutcome) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.selection = selection
    self.captureSession = captureSession
    self.exclusions = exclusions
    self.limits = limits
    self.onFinish = onFinish
    self.onCancel = onCancel
  }

  func start() {
    guard !isRunning else { return }
    isRunning = true
    let hud = ScrollingCaptureHUDWindow(
      displayID: selection.displayID,
      anchor: selection.rect,
      onFinish: { [weak self] in self?.finish() },
      onCancel: { [weak self] in self?.cancel() }
    )
    self.hud = hud
    hud.present()
    task = Task { [weak self] in await self?.collect() }
  }

  func finish() {
    guard isRunning else { return }
    isRunning = false
    task?.cancel()
    task = nil
    hud?.dismiss()
    hud = nil
    let captured = frames
    let measured = profiles
    frames.removeAll()
    profiles.removeAll()
    Task { [weak self] in
      let outcome = await Task.detached(priority: .userInitiated) {
        ScrollStitcher.stitch(frames: captured, profiles: measured)
      }.value
      self?.onFinish(outcome)
    }
  }

  func cancel() {
    guard isRunning else { return }
    isRunning = false
    task?.cancel()
    task = nil
    hud?.dismiss()
    hud = nil
    frames.removeAll()
    profiles.removeAll()
    onCancel()
  }

  private func collect() async {
    let clock = ContinuousClock()
    let started = clock.now
    var failures = 0
    while !Task.isCancelled {
      if frameCount >= limits.maxFrames {
        return finish()
      }
      if started.duration(to: clock.now) >= limits.maxDuration {
        return finish()
      }
      do {
        let result = try await captureSession.capture(selection, excludingApplications: exclusions)
        failures = 0
        if let profile = await measure(result.image), profiles.last != profile {
          frames.append(result.image)
          profiles.append(profile)
          sourcePixels += result.image.width * result.image.height
          frameCount = frames.count
          hud?.update(count: frameCount)
          if sourcePixels > limits.maxSourcePixels {
            return finish()
          }
        }
      } catch {
        failures += 1
        if failures >= limits.maxConsecutiveFailures {
          return finish()
        }
      }
      try? await Task.sleep(for: limits.interval)
    }
  }

  private func measure(_ image: CGImage) async -> ScrollStitcher.FrameProfile? {
    await Task.detached(priority: .utility) {
      ScrollStitcher.profile(for: image)
    }.value
  }
}
