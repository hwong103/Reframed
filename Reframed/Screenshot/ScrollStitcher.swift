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
  static let outputPixelBudget = 120_000_000

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
    var message = ""
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
    let usable = previous.height - topInset - bottomInset
    guard usable >= minUsable else { return nil }
    let band = min(max(usable / 4, minBand), maxBand)
    let upper = min(maxDelta, usable - band)
    guard upper >= 1 else { return nil }
    let start = topInset + usable - band
    let window = previous.samples[(start * width)..<((start + band) * width)]
    guard
      let low = window.min(),
      let high = window.max(),
      Int(high) - Int(low) >= minVariation
    else {
      return (delta: 0, error: -1, runnerUp: -1, isUncertain: true, isDuplicate: false)
    }
    var errors = [Double](repeating: 0, count: upper + 1)
    for delta in 0...upper {
      errors[delta] = meanError(previous.samples, next.samples, start: start, width: width, band: band, delta: delta)
    }
    if errors[0] <= duplicateError {
      return (delta: 0, error: errors[0], runnerUp: errors[0], isUncertain: false, isDuplicate: true)
    }
    var best = 1
    for delta in 1...upper where errors[delta] < errors[best] {
      best = delta
    }
    var runner = Double.greatestFiniteMagnitude
    for delta in 1...upper where abs(delta - best) > 2 {
      runner = min(runner, errors[delta])
    }
    let error = errors[best]
    let certain = error <= acceptError && runner - error >= margin
    return (delta: best, error: error, runnerUp: runner, isUncertain: !certain, isDuplicate: false)
  }

  private static func meanError(
    _ previous: [UInt8],
    _ next: [UInt8],
    start: Int,
    width: Int,
    band: Int,
    delta: Int
  ) -> Double {
    var total = 0
    previous.withUnsafeBufferPointer { source in
      next.withUnsafeBufferPointer { target in
        for row in 0..<band {
          let left = (start + row) * width
          let right = (start + row - delta) * width
          for column in 0..<width {
            total += abs(Int(source[left + column]) - Int(target[right + column]))
          }
        }
      }
    }
    return Double(total) / Double(band * width)
  }
}
