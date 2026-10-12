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
    let cropX = crop?.minX ?? 0
    let cropY = crop?.minY ?? 0
    let visible = crop ?? CGRect(origin: .zero, size: document.pixelSize)
    let inner = item.bounds.standardized.integral.intersection(visible).integral
    let halo = CGFloat(max(0, padding))
    let expanded = inner.insetBy(dx: -halo, dy: -halo).integral.intersection(visible).integral
    guard inner.width >= 1, inner.height >= 1, expanded.width >= 1, expanded.height >= 1,
      let snapshot = context.makeImage()
    else {
      return
    }
    let width = Int(expanded.width)
    let height = Int(expanded.height)
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    buffer.withUnsafeMutableBytes { raw in
      guard
        let temp = CGContext(
          data: raw.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        )
      else {
        return
      }
      let tempViewport = Viewport(
        originX: expanded.minX - cropX,
        originY: expanded.minY - cropY,
        outputHeight: CGFloat(height)
      )
      temp.draw(snapshot, in: tempViewport.imageRect(width: snapshot.width, height: snapshot.height))
    }
    transform(&buffer, width, height)
    let innerWidth = Int(inner.width)
    let innerHeight = Int(inner.height)
    let offsetX = Int(inner.minX - expanded.minX)
    let offsetY = Int(inner.minY - expanded.minY)
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

  static func boxBlur(_ buffer: inout [UInt8], width: Int, height: Int, radius: Int) {
    let r = max(0, radius)
    guard r > 0, width > 0, height > 0 else {
      return
    }
    let count = 2 * r + 1
    var horizontal = buffer
    for y in 0..<height {
      for x in 0..<width {
        var sumRed = 0
        var sumGreen = 0
        var sumBlue = 0
        var sumAlpha = 0
        for dx in -r...r {
          let sampleX = min(max(x + dx, 0), width - 1)
          let index = (y * width + sampleX) * 4
          sumRed += Int(buffer[index])
          sumGreen += Int(buffer[index + 1])
          sumBlue += Int(buffer[index + 2])
          sumAlpha += Int(buffer[index + 3])
        }
        let output = (y * width + x) * 4
        horizontal[output] = UInt8(sumRed / count)
        horizontal[output + 1] = UInt8(sumGreen / count)
        horizontal[output + 2] = UInt8(sumBlue / count)
        horizontal[output + 3] = UInt8(sumAlpha / count)
      }
    }
    for y in 0..<height {
      for x in 0..<width {
        var sumRed = 0
        var sumGreen = 0
        var sumBlue = 0
        var sumAlpha = 0
        for dy in -r...r {
          let sampleY = min(max(y + dy, 0), height - 1)
          let index = (sampleY * width + x) * 4
          sumRed += Int(horizontal[index])
          sumGreen += Int(horizontal[index + 1])
          sumBlue += Int(horizontal[index + 2])
          sumAlpha += Int(horizontal[index + 3])
        }
        let output = (y * width + x) * 4
        buffer[output] = UInt8(sumRed / count)
        buffer[output + 1] = UInt8(sumGreen / count)
        buffer[output + 2] = UInt8(sumBlue / count)
        buffer[output + 3] = UInt8(sumAlpha / count)
      }
    }
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
