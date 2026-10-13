import CoreGraphics
import Foundation

enum ScrollStitcher {
  static let profileWidth = 48
  static let maxDelta = 2000
  static let maxBand = 192
  static let minBand = 32
  static let minUsable = 64
  static let minVariation = 6
  static let duplicateError = 1.5
  static let acceptError = 6.0
  static let margin = 2.0
  static let rowTolerance = 2
  static let validationBands = 3
  static let outputPixelBudget = 120_000_000

  enum Termination: Sendable, Equatable {
    case userFinish
    case frameLimit
    case timeLimit
    case memoryLimit
    case captureFailures
  }

  struct FrameProfile: Equatable, Sendable {
    let width: Int
    let height: Int
    let samples: [UInt8]
  }

  struct StitchOutcome: Sendable {
    var image: CGImage?
    var offsets: [Int] = []
    var uncertainJoins: [Int] = []
    var droppedDuplicates = 0
    var headerRows = 0
    var footerRows = 0
    var termination: Termination = .userFinish
    var message = ""
  }

  struct BandScan: Sendable {
    let delta: Int
    let error: Double
    let runnerUp: Double
  }

  typealias OffsetMatch = (delta: Int, error: Double, runnerUp: Double, isUncertain: Bool, isDuplicate: Bool)

  static func profile(for image: CGImage) -> FrameProfile? {
    let width = profileWidth
    let height = image.height
    guard width >= 8, height >= 8 else { return nil }
    var buffer = [UInt8](repeating: 0, count: width * height)
    let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
      guard let base = raw.baseAddress else { return false }
      let space = CGColorSpaceCreateDeviceGray()
      guard
        let context = CGContext(
          data: base,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width,
          space: space,
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      else { return false }
      context.interpolationQuality = .medium
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    return FrameProfile(width: width, height: height, samples: buffer)
  }

  static func offset(
    betweenPrevious previous: FrameProfile,
    and next: FrameProfile,
    topInset: Int = 0,
    bottomInset: Int = 0
  ) -> OffsetMatch? {
    let width = previous.width
    guard width > 0, previous.width == next.width, previous.height == next.height else { return nil }
    let height = previous.height
    let usable = height - topInset - bottomInset
    guard usable >= minUsable else { return nil }
    let band = min(max(usable / 4, minBand), maxBand)
    let upper = min(maxDelta, usable - band)
    guard upper >= 1 else { return nil }
    let whole = wholeFrameError(previous: previous, next: next)
    if whole <= duplicateError {
      return (delta: 0, error: whole, runnerUp: whole, isUncertain: false, isDuplicate: true)
    }
    let primaryStart = topInset + usable - band
    guard
      let primary = scanDelta(
        previous: previous,
        next: next,
        start: primaryStart,
        band: band,
        upper: upper
      )
    else { return doubtful() }
    var votes = 0
    var agrees = true
    let starts = validationStarts(delta: primary.delta, low: topInset, high: height - bottomInset, band: band)
    for start in starts where start != primaryStart {
      guard
        let other = scanDelta(previous: previous, next: next, start: start, band: band, upper: upper)
      else { continue }
      guard other.error <= acceptError, abs(other.delta - primary.delta) <= rowTolerance else {
        agrees = false
        break
      }
      votes += 1
    }
    let certain =
      agrees && votes >= 1 && primary.error <= acceptError && primary.runnerUp - primary.error >= margin
    return (
      delta: primary.delta,
      error: primary.error,
      runnerUp: primary.runnerUp,
      isUncertain: !certain,
      isDuplicate: false
    )
  }

  static func validationStarts(delta: Int, low: Int, high: Int, band: Int) -> [Int] {
    let first = max(low, delta)
    let last = high - band
    guard last > first, validationBands > 1 else { return [first] }
    let step = (last - first) / (validationBands - 1)
    guard step >= 1 else { return [first, last] }
    return (0..<validationBands).map { first + $0 * step }
  }

  private static func doubtful() -> OffsetMatch {
    (delta: 0, error: -1, runnerUp: -1, isUncertain: true, isDuplicate: false)
  }

  private static func wholeFrameError(previous: FrameProfile, next: FrameProfile) -> Double {
    let width = previous.width
    let rows = min(previous.height, next.height)
    var total = 0
    previous.samples.withUnsafeBufferPointer { source in
      next.samples.withUnsafeBufferPointer { target in
        for index in 0..<(width * rows) {
          total += abs(Int(source[index]) - Int(target[index]))
        }
      }
    }
    return Double(total) / Double(max(1, width * rows))
  }

  private static func scanDelta(
    previous: FrameProfile,
    next: FrameProfile,
    start: Int,
    band: Int,
    upper: Int
  ) -> BandScan? {
    let width = previous.width
    guard start >= 0, start + band <= previous.height else { return nil }
    let limit = min(upper, start)
    guard limit >= 1 else { return nil }
    let window = previous.samples[(start * width)..<((start + band) * width)]
    guard
      let low = window.min(),
      let high = window.max(),
      Int(high) - Int(low) >= minVariation
    else { return nil }
    var errors = [Double](repeating: 0, count: limit + 1)
    for delta in 0...limit {
      guard !Task.isCancelled else { return nil }
      errors[delta] = meanError(previous.samples, next.samples, start: start, width: width, band: band, delta: delta)
    }
    var best = 0
    for delta in 1...limit where errors[delta] < errors[best] {
      best = delta
    }
    var runner = Double.greatestFiniteMagnitude
    for delta in 0...limit where abs(delta - best) > rowTolerance {
      runner = min(runner, errors[delta])
    }
    guard runner < Double.greatestFiniteMagnitude else { return nil }
    return BandScan(delta: best, error: errors[best], runnerUp: runner)
  }
}
