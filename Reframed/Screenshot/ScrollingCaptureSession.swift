import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class ScrollingCaptureSession {
  enum Phase: Equatable {
    case idle
    case preparing
    case collecting
    case stitching
    case finished
  }

  struct Limits {
    var maxFrames = 120
    var maxDuration: Duration = .seconds(60)
    var maxSourcePixels = 120_000_000
    var interval: Duration = .milliseconds(200)
    var maxConsecutiveFailures = 3
  }

  private static var issued = 0

  let generation: Int
  private(set) var phase: Phase = .idle
  private(set) var frameCount = 0

  var isEscapable: Bool { phase == .preparing || phase == .collecting || phase == .stitching }

  private let selection: SelectionRect
  private let captureSession: ScreenshotSession
  private let exclusions: [SCRunningApplication]
  private let limits: Limits

  private var onFinish: ((ScrollStitcher.StitchOutcome) -> Void)?
  private var onCancel: (() -> Void)?
  private var frames: [CGImage] = []
  private var profiles: [ScrollStitcher.FrameProfile] = []
  private var sourcePixels = 0
  private var collectTask: Task<Void, Never>?
  private var stitchTask: Task<ScrollStitcher.StitchOutcome, Never>?
  private var hud: ScrollingCaptureHUDWindow?

  init(
    selection: SelectionRect,
    captureSession: ScreenshotSession,
    exclusions: [SCRunningApplication],
    limits: Limits = Limits()
  ) {
    Self.issued += 1
    self.generation = Self.issued
    self.selection = selection
    self.captureSession = captureSession
    self.exclusions = exclusions
    self.limits = limits
  }

  func connect(
    onFinish: @escaping (ScrollStitcher.StitchOutcome) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.onFinish = onFinish
    self.onCancel = onCancel
  }

  func start() {
    guard phase == .idle, onFinish != nil else { return }
    phase = .preparing
    let hud = ScrollingCaptureHUDWindow(
      displayID: selection.displayID,
      anchor: selection.rect,
      onFinish: { [weak self] in self?.finish() },
      onCancel: { [weak self] in self?.cancel() }
    )
    self.hud = hud
    hud.present()
    collectTask = Task { [weak self] in await self?.collect() }
  }

  func finish(reason: ScrollStitcher.Termination = .userFinish) {
    guard phase == .collecting || phase == .preparing else { return }
    phase = .stitching
    collectTask?.cancel()
    collectTask = nil
    dismissHUD()
    let captured = frames
    let measured = profiles
    frames.removeAll()
    profiles.removeAll()
    let generation = generation
    let worker = Task.detached(priority: .userInitiated) {
      ScrollStitcher.stitch(frames: captured, profiles: measured, termination: reason)
    }
    stitchTask = worker
    Task { [weak self] in
      let outcome = await worker.value
      guard let self, !Task.isCancelled, self.generation == generation, self.phase == .stitching else { return }
      self.deliver(outcome)
    }
  }

  func cancel() {
    guard phase != .idle, phase != .finished else { return }
    phase = .finished
    collectTask?.cancel()
    collectTask = nil
    stitchTask?.cancel()
    stitchTask = nil
    dismissHUD()
    frames.removeAll()
    profiles.removeAll()
    let handler = onCancel
    onFinish = nil
    onCancel = nil
    handler?()
  }

  private func collect() async {
    guard phase == .preparing else { return }
    phase = .collecting
    let clock = ContinuousClock()
    let started = clock.now
    var failures = 0
    while isCollecting {
      if frameCount >= limits.maxFrames {
        return finish(reason: .frameLimit)
      }
      if started.duration(to: clock.now) >= limits.maxDuration {
        return finish(reason: .timeLimit)
      }
      do {
        let result = try await captureSession.frameImage(selection, excludingApplications: exclusions)
        guard isCollecting else { return }
        failures = 0
        if let profile = await measure(result.image) {
          guard isCollecting else { return }
          if profiles.last != profile {
            let pixels = result.image.width * result.image.height
            guard sourcePixels + pixels <= limits.maxSourcePixels else {
              return finish(reason: .memoryLimit)
            }
            frames.append(result.image)
            profiles.append(profile)
            sourcePixels += pixels
            frameCount = frames.count
            hud?.update(count: frameCount)
          }
        }
      } catch {
        guard isCollecting else { return }
        failures += 1
        if failures >= limits.maxConsecutiveFailures {
          return finish(reason: .captureFailures)
        }
      }
      try? await Task.sleep(for: limits.interval)
    }
  }

  private var isCollecting: Bool { !Task.isCancelled && phase == .collecting }

  private func measure(_ image: CGImage) async -> ScrollStitcher.FrameProfile? {
    await Task.detached(priority: .utility) {
      ScrollStitcher.profile(for: image)
    }.value
  }

  private func deliver(_ outcome: ScrollStitcher.StitchOutcome) {
    phase = .finished
    let handler = onFinish
    onFinish = nil
    onCancel = nil
    handler?(outcome)
  }

  private func dismissHUD() {
    hud?.dismiss()
    hud = nil
  }
}
