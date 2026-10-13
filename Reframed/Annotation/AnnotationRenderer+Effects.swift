import CoreGraphics
import Foundation

extension AnnotationRenderer {
  static func applyBlur(
    _ item: AnnotationItem,
    in context: CGContext,
    viewport: Viewport,
    document: AnnotationDocument
  ) {
    let radius = max(0, Int(item.style.blurRadius.rounded()))
    transformRegion(item, in: context, viewport: viewport, document: document, padding: radius) { buffer, width, height in
      boxBlur(&buffer, width: width, height: height, radius: radius)
    }
  }

  static func applyPixelate(
    _ item: AnnotationItem,
    in context: CGContext,
    viewport: Viewport,
    document: AnnotationDocument
  ) {
    let block = Int(item.style.blurRadius.rounded())
    transformRegion(item, in: context, viewport: viewport, document: document, padding: 0) { buffer, width, height in
      pixelate(&buffer, width: width, height: height, block: block)
    }
  }

  static func transformRegion(
    _ item: AnnotationItem,
    in context: CGContext,
    viewport: Viewport,
    document: AnnotationDocument,
    padding: Int,
    transform: (inout [UInt8], Int, Int) -> Void
  ) {
    let crop = cropRect(for: document)
    let visible = crop ?? CGRect(origin: .zero, size: document.pixelSize)
    let inner = item.bounds.standardized.integral.intersection(visible).integral
    let halo = CGFloat(max(0, padding))
    let expanded = inner.insetBy(dx: -halo, dy: -halo).integral.intersection(visible).integral
    guard inner.width >= 1, inner.height >= 1, expanded.width >= 1, expanded.height >= 1 else {
      return
    }
    let bounds = CGRect(x: 0, y: 0, width: context.width, height: context.height)
    let expandedRect = viewport.rect(expanded).integral.intersection(bounds).integral
    guard expandedRect.width >= 1, expandedRect.height >= 1,
      let region = regionBuffer(from: context, rect: expandedRect)
    else { return }
    let width = Int(expandedRect.width)
    let height = Int(expandedRect.height)
    var buffer = region
    transform(&buffer, width, height)

    let innerRect = viewport.rect(inner).integral.intersection(bounds).integral
    let offsetX = Int(innerRect.minX - expandedRect.minX)
    let offsetY = Int(expandedRect.maxY - innerRect.maxY)
    let innerWidth = Int(innerRect.width)
    let innerHeight = Int(innerRect.height)
    guard innerWidth >= 1, innerHeight >= 1, offsetX >= 0, offsetY >= 0,
      offsetX + innerWidth <= width, offsetY + innerHeight <= height
    else {
      return
    }
    var innerBuffer = [UInt8](repeating: 0, count: innerWidth * innerHeight * 4)
    for y in 0..<innerHeight {
      for x in 0..<innerWidth {
        let source = ((y + offsetY) * width + (x + offsetX)) * 4
        let destination = (y * innerWidth + x) * 4
        innerBuffer[destination] = buffer[source]
        innerBuffer[destination + 1] = buffer[source + 1]
        innerBuffer[destination + 2] = buffer[source + 2]
        innerBuffer[destination + 3] = buffer[source + 3]
      }
    }
    guard let regionImage = image(from: innerBuffer, width: innerWidth, height: innerHeight) else {
      return
    }
    context.saveGState()
    context.setBlendMode(.copy)
    context.interpolationQuality = .none
    context.draw(regionImage, in: viewport.rect(inner))
    context.restoreGState()
  }

  private static func regionBuffer(from context: CGContext, rect: CGRect) -> [UInt8]? {
    guard let base = context.data else { return nil }
    let width = Int(rect.width)
    let height = Int(rect.height)
    let stride = context.bytesPerRow
    let firstRow = context.height - Int(rect.maxY)
    guard firstRow >= 0, firstRow + height <= context.height else { return nil }
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    buffer.withUnsafeMutableBytes { raw in
      guard let destination = raw.baseAddress else { return }
      for row in 0..<height {
        let source = (firstRow + row) * stride + Int(rect.minX) * 4
        memcpy(destination.advanced(by: row * width * 4), base.advanced(by: source), width * 4)
      }
    }
    return buffer
  }

  static func boxBlur(_ buffer: inout [UInt8], width: Int, height: Int, radius: Int) {
    let r = max(0, radius)
    guard r > 0, width > 0, height > 0 else {
      return
    }
    let count = 2 * r + 1
    var horizontal = buffer
    blurAxis(&buffer, into: &horizontal, width: width, height: height, radius: r, count: count, horizontal: true)
    blurAxis(&horizontal, into: &buffer, width: width, height: height, radius: r, count: count, horizontal: false)
  }

  private static func blurAxis(
    _ source: inout [UInt8],
    into destination: inout [UInt8],
    width: Int,
    height: Int,
    radius: Int,
    count: Int,
    horizontal: Bool
  ) {
    var sums = [0, 0, 0, 0]
    let outer = horizontal ? height : width
    let inner = horizontal ? width : height
    for line in 0..<outer {
      sums = [0, 0, 0, 0]
      for offset in -radius...radius {
        let index = pixelIndex(line, clamp(offset, inner), width: width, horizontal: horizontal)
        for channel in 0..<4 { sums[channel] += Int(source[index + channel]) }
      }
      for sample in 0..<inner {
        let out = pixelIndex(line, sample, width: width, horizontal: horizontal)
        for channel in 0..<4 { destination[out + channel] = UInt8(sums[channel] / count) }
        let leaving = pixelIndex(line, clamp(sample - radius, inner), width: width, horizontal: horizontal)
        let entering = pixelIndex(line, clamp(sample + radius + 1, inner), width: width, horizontal: horizontal)
        for channel in 0..<4 {
          sums[channel] += Int(source[entering + channel]) - Int(source[leaving + channel])
        }
      }
    }
  }

  private static func pixelIndex(_ line: Int, _ sample: Int, width: Int, horizontal: Bool) -> Int {
    (horizontal ? line * width + sample : sample * width + line) * 4
  }

  private static func clamp(_ value: Int, _ limit: Int) -> Int {
    min(max(value, 0), limit - 1)
  }

  static func pixelate(_ buffer: inout [UInt8], width: Int, height: Int, block: Int) {
    let size = max(2, block)
    guard width > 0, height > 0 else {
      return
    }
    for blockY in stride(from: 0, to: height, by: size) {
      for blockX in stride(from: 0, to: width, by: size) {
        let sampleX = min(blockX, width - 1)
        let sampleY = min(blockY, height - 1)
        let source = (sampleY * width + sampleX) * 4
        let red = buffer[source]
        let green = buffer[source + 1]
        let blue = buffer[source + 2]
        let alpha = buffer[source + 3]
        for y in blockY..<min(blockY + size, height) {
          for x in blockX..<min(blockX + size, width) {
            let index = (y * width + x) * 4
            buffer[index] = red
            buffer[index + 1] = green
            buffer[index + 2] = blue
            buffer[index + 3] = alpha
          }
        }
      }
    }
  }
}
