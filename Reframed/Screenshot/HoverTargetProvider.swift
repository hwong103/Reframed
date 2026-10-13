import CoreGraphics
import Foundation

@MainActor
final class HoverTargetProvider {
  private let windowController = WindowController()
  private var lastLookup: TimeInterval = 0
  private var cached: HoverTarget?

  func target(at point: CGPoint) -> HoverTarget? {
    let now = Date.timeIntervalSinceReferenceDate
    if now - lastLookup < 0.1 {
      return cached
    }
    lastLookup = now
    cached = windowController.findOnScreenTarget(at: point)
    return cached
  }
}
