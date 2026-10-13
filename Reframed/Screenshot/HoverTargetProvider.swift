import CoreGraphics
import Foundation

@MainActor
final class HoverTargetProvider {
  private let windowController = WindowController()
  private let frozenTargets: [HoverTarget]
  private var lastLookup: TimeInterval = 0
  private var cached: HoverTarget?

  init(frozenTargets: [HoverTarget] = []) {
    self.frozenTargets = frozenTargets
  }

  func target(at point: CGPoint) -> HoverTarget? {
    if !frozenTargets.isEmpty {
      return frozenTargets.first { $0.bounds.contains(point) }
    }
    let now = Date.timeIntervalSinceReferenceDate
    if now - lastLookup < 0.1 {
      return cached
    }
    lastLookup = now
    cached = windowController.findOnScreenTarget(at: point)
    return cached
  }
}
