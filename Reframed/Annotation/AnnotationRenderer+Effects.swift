import CoreGraphics
import Foundation

extension AnnotationRenderer {
  static func applyBlur(_ item: AnnotationItem, in context: CGContext, viewport: Viewport, document: AnnotationDocument) {
    let radius = max(0, Int(item.style.blurRadius.rounded()))
    transformRegion(item, in: context, viewport: viewport, document: document, padding: radius) { buffer, width, height in
      boxBlur(&buffer, width: width, height: height, radius: radius)
    }
  }

  static func applyPixelate(_ item: AnnotationItem, in context: CGContext, viewport: Viewport, document: AnnotationDocument) {
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
    guard inner.width >= 1, inner.height >= 1, expanded.width >= 1, expanded.height >= 1 else { return }
    let bounds = CGRect(x: 0, y: 0, width: context.width, height: context.height)
    let expandedRect = viewport.rect(expanded).integral.intersection(bounds).integral
    guard expandedRect.width >= 1, expandedRect.height >= 1 else { return }
    let width = Int(expandedRect.width)
    let height = Int(expandedRect.height)
    guard var buffer = regionBuffer(from: context, rect: expandedRect) else { return }
    transform(&buffer, width, height)
    let innerRect = viewport.rect(inner).integral.intersection(bounds).integral
    let innerWidth = Int(innerRect.width)
    let innerHeight = Int(innerRect.height)
    let offsetX = Int(innerRect.minX - expandedRect.minX)
    let offsetY = Int(expandedRect.maxY - innerRect.maxY)
    guard innerWidth >= 1, innerHeight >= 1, offsetX >= 0, offsetY >= 0,
      offsetX + innerWidth <= width, offsetY + innerHeight <= height
    else { return }
    let rowBytes = innerWidth * 4
    let slice = [UInt8](unsafeUninitializedCapacity: rowBytes * innerHeight) { raw, initialized in
      guard let destination = raw.baseAddress else { return }
      buffer.withUnsafeBufferPointer { source in
        guard let base = source.baseAddress else { return }
        for row in 0..<innerHeight {
          let start = ((row + offsetY) * width + offsetX) * 4
          memcpy(destination.advanced(by: row * rowBytes), base.advanced(by: start), rowBytes)
        }
      }
      initialized = rowBytes * innerHeight
    }
    guard let regionImage = image(from: slice, width: innerWidth, height: innerHeight) else { return }
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
    guard width > 0, height > 0, firstRow >= 0, firstRow + height <= context.height else { return nil }
    return [UInt8](unsafeUninitializedCapacity: width * height * 4) { raw, initialized in
      guard let destination = raw.baseAddress else { return }
      for row in 0..<height {
        let source = (firstRow + row) * stride + Int(rect.minX) * 4
        memcpy(destination.advanced(by: row * width * 4), base.advanced(by: source), width * 4)
      }
      initialized = width * height * 4
    }
  }

  static func boxBlur(_ buffer: inout [UInt8], width: Int, height: Int, radius: Int) {
    let r = max(0, radius)
    guard r > 0, width > 0, height > 0 else { return }
    let count = 2 * r + 1
    var quotients = [UInt8](repeating: 0, count: 255 * count + 1)
    for value in 0...(255 * count) { quotients[value] = UInt8(value / count) }
    var horizontal = buffer
    blurAxis(&buffer, into: &horizontal, width: width, height: height, radius: r, quotients: quotients, horizontal: true)
    blurAxis(&horizontal, into: &buffer, width: width, height: height, radius: r, quotients: quotients, horizontal: false)
  }

  private static func blurAxis(
    _ source: inout [UInt8],
    into destination: inout [UInt8],
    width: Int,
    height: Int,
    radius: Int,
    quotients: [UInt8],
    horizontal: Bool
  ) {
    let outer = horizontal ? height : width
    let inner = horizontal ? width : height
    guard inner > 0, outer > 0 else { return }
    let step = horizontal ? 4 : width * 4
    let lineStride = horizontal ? width * 4 : 4
    let last = inner - 1
    source.withUnsafeBufferPointer { src in
      destination.withUnsafeMutableBufferPointer { dst in
        quotients.withUnsafeBufferPointer { table in
          guard let srcBase = src.baseAddress, let dstBase = dst.baseAddress, let table = table.baseAddress else { return }
          for line in 0..<outer {
            let lineBase = line * lineStride
            var s0 = 0
            var s1 = 0
            var s2 = 0
            var s3 = 0
            for offset in -radius...radius {
              let index = lineBase + min(max(offset, 0), last) * step
              s0 += Int(srcBase[index])
              s1 += Int(srcBase[index + 1])
              s2 += Int(srcBase[index + 2])
              s3 += Int(srcBase[index + 3])
            }
            var leaving = lineBase
            var entering = lineBase + min(radius + 1, last) * step
            for sample in 0..<inner {
              let out = lineBase + sample * step
              dstBase[out] = table[s0]
              dstBase[out + 1] = table[s1]
              dstBase[out + 2] = table[s2]
              dstBase[out + 3] = table[s3]
              s0 += Int(srcBase[entering]) - Int(srcBase[leaving])
              s1 += Int(srcBase[entering + 1]) - Int(srcBase[leaving + 1])
              s2 += Int(srcBase[entering + 2]) - Int(srcBase[leaving + 2])
              s3 += Int(srcBase[entering + 3]) - Int(srcBase[leaving + 3])
              if sample + radius + 1 < last { entering += step }
              if sample >= radius { leaving += step }
            }
          }
        }
      }
    }
  }

  static func pixelate(_ buffer: inout [UInt8], width: Int, height: Int, block: Int) {
    let size = max(2, block)
    guard width > 0, height > 0 else { return }
    buffer.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress else { return }
      for blockY in stride(from: 0, to: height, by: size) {
        let yEnd = min(blockY + size, height)
        for blockX in stride(from: 0, to: width, by: size) {
          let xEnd = min(blockX + size, width)
          let run = xEnd - blockX
          let source = base.advanced(by: (blockY * width + blockX) * 4)
          var pattern: UInt32 = 0
          memcpy(&pattern, source, 4)
          for y in blockY..<yEnd {
            let row = base.advanced(by: (y * width + blockX) * 4)
            if run >= 8 {
              memset_pattern4(row, &pattern, run * 4)
            } else {
              for offset in stride(from: 0, to: run * 4, by: 4) {
                memcpy(row.advanced(by: offset), &pattern, 4)
              }
            }
          }
        }
      }
    }
  }
}
