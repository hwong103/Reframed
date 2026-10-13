import CoreGraphics
import Foundation

extension ScrollStitcher {
  static func stitch(frames: [CGImage], profiles measured: [FrameProfile]? = nil) -> StitchOutcome {
    guard frames.count >= 2 else { return refused("Scrolling capture needs at least two frames.") }
    let profiles = measured?.count == frames.count ? measured! : frames.compactMap { profile(for: $0) }
    guard !profiles.isEmpty, profiles.count == frames.count else {
      return refused("A captured frame could not be measured.")
    }
    let width = frames[0].width
    let height = profiles.map(\.height).min() ?? 0
    let uniform = profiles.allSatisfy { $0.height == height }
    let framed = frames.allSatisfy { $0.width == width && $0.height == height }
    guard width > 0, height >= minUsable, uniform, framed else {
      return refused("The captured frames did not share one size.")
    }
    let insets = fixedInsets(profiles)
    let band = height - insets.header - insets.footer
    guard band >= 1, insets.header + insets.footer < height / 2 else {
      return refused("The region did not appear to scroll, so there is nothing to stitch.")
    }
    var outcome = StitchOutcome(headerRows: insets.header, footerRows: insets.footer)
    var cumulative = [0]
    for index in 1..<frames.count {
      guard
        let match = offset(
          betweenPrevious: profiles[index - 1],
          and: profiles[index],
          topInset: insets.header,
          bottomInset: insets.footer
        )
      else { return refused("Two frames could not be compared.") }
      outcome.offsets.append(match.delta)
      cumulative.append(cumulative[cumulative.count - 1] + match.delta)
      if match.isDuplicate {
        outcome.droppedDuplicates += 1
      } else if match.isUncertain {
        outcome.uncertainJoins.append(index - 1)
      }
    }
    let composedHeight = cumulative[cumulative.count - 1] + band
    guard composedHeight > band else {
      return refused("The page did not scroll, so there is nothing to stitch.")
    }
    let (pixels, overflow) = width.multipliedReportingOverflow(by: composedHeight)
    guard !overflow, pixels <= outputPixelBudget else {
      return refused("The stitched image would be too large to build.")
    }
    guard
      let image = compose(
        frames: frames,
        cumulative: cumulative,
        header: insets.header,
        band: band,
        width: width,
        height: composedHeight
      )
    else { return refused("The stitched image could not be rendered.") }
    outcome.image = image
    outcome.message = summary(frames: frames.count, outcome: outcome)
    return outcome
  }

  static func fixedInsets(_ profiles: [FrameProfile]) -> (header: Int, footer: Int) {
    guard let first = profiles.first, first.width > 0, profiles.count > 1 else { return (0, 0) }
    let height = profiles.map(\.height).min() ?? 0
    let limit = height / 3
    guard limit >= 1 else { return (0, 0) }
    func fixed(_ row: Int) -> Bool {
      for profile in profiles.dropFirst() {
        guard profile.width == first.width, profile.height > row else { return false }
        for column in 0..<first.width {
          let index = row * first.width + column
          if abs(Int(profile.samples[index]) - Int(first.samples[index])) > rowTolerance {
            return false
          }
        }
      }
      return true
    }
    var header = 0
    while header < limit, fixed(header) {
      header += 1
    }
    var footer = 0
    while footer < limit, fixed(height - 1 - footer) {
      footer += 1
    }
    return (header, footer)
  }

  private static func compose(
    frames: [CGImage],
    cumulative: [Int],
    header: Int,
    band: Int,
    width: Int,
    height: Int
  ) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let slice = CGRect(x: 0, y: header, width: width, height: band)
    for (index, frame) in frames.enumerated() {
      guard let crop = frame.cropping(to: slice) else { return nil }
      let origin = height - cumulative[index] - band
      guard origin >= 0 else { return nil }
      context.draw(crop, in: CGRect(x: 0, y: origin, width: width, height: band))
    }
    return context.makeImage()
  }

  private static func summary(frames: Int, outcome: StitchOutcome) -> String {
    var message = "Stitched \(frames) frames"
    if outcome.droppedDuplicates > 0 {
      message += ", \(outcome.droppedDuplicates) duplicate skipped"
    }
    if !outcome.uncertainJoins.isEmpty {
      message += ", \(outcome.uncertainJoins.count) doubtful"
    }
    return message
  }

  private static func refused(_ message: String) -> StitchOutcome {
    StitchOutcome(message: message)
  }
}
