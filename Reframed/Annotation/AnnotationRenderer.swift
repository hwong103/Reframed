import CoreGraphics
import Foundation

enum AnnotationRenderer {
  static let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue

  static var colorSpace: CGColorSpace {
    CGColorSpace(name: CGColorSpace.sRGB)!
  }

  static func cgColor(_ color: CodableColor) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [color.r, color.g, color.b, color.a])!
  }

  struct Viewport {
    let originX: CGFloat
    let originY: CGFloat
    let outputHeight: CGFloat

    func point(_ point: CGPoint) -> CGPoint {
      CGPoint(x: point.x - originX, y: outputHeight - (point.y - originY))
    }

    func rect(_ rect: CGRect) -> CGRect {
      CGRect(
        x: rect.minX - originX,
        y: outputHeight - (rect.maxY - originY),
        width: rect.width,
        height: rect.height
      )
    }

    func imageRect(width: Int, height: Int) -> CGRect {
      CGRect(
        x: -originX,
        y: outputHeight + originY - CGFloat(height),
        width: CGFloat(width),
        height: CGFloat(height)
      )
    }
  }

  static func cropRect(for document: AnnotationDocument) -> CGRect? {
    guard let crop = document.cropRect else {
      return nil
    }
    let bounds = CGRect(origin: .zero, size: document.pixelSize)
    let clamped = crop.standardized.integral.intersection(bounds)
    guard clamped.width >= 1, clamped.height >= 1 else {
      return nil
    }
    return clamped
  }

  static func outputSize(for document: AnnotationDocument) -> CGSize {
    guard let crop = cropRect(for: document) else {
      return document.pixelSize
    }
    return CGSize(width: crop.width, height: crop.height)
  }

  static func viewport(for document: AnnotationDocument) -> Viewport {
    let crop = cropRect(for: document)
    return Viewport(
      originX: crop?.minX ?? 0,
      originY: crop?.minY ?? 0,
      outputHeight: outputSize(for: document).height
    )
  }

  static func render(_ document: AnnotationDocument, image: CGImage, into context: CGContext) {
    if document.hasEffects, let composed = makeImage(document, image: image) {
      context.saveGState()
      context.interpolationQuality = .none
      let rect = CGRect(
        origin: .zero,
        size: CGSize(width: composed.width, height: composed.height)
      )
      context.draw(composed, in: rect)
      context.restoreGState()
      return
    }
    renderDirect(document, image: image, into: context)
  }

  static func renderDirect(_ document: AnnotationDocument, image: CGImage, into context: CGContext) {
    let viewport = viewport(for: document)
    context.saveGState()
    context.interpolationQuality = .none
    context.draw(image, in: viewport.imageRect(width: image.width, height: image.height))
    context.restoreGState()
    for item in document.items {
      draw(item, in: context, viewport: viewport, document: document)
    }
  }

  static func makeImage(_ document: AnnotationDocument, image: CGImage) -> CGImage? {
    let size = outputSize(for: document)
    let width = Int(size.width)
    let height = Int(size.height)
    guard width > 0, height > 0 else {
      return nil
    }
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    var result: CGImage?
    buffer.withUnsafeMutableBytes { raw in
      guard let context = bitmapContext(raw.baseAddress, width: width, height: height) else { return }
      renderDirect(document, image: image, into: context)
      result = context.makeImage()
    }
    return result
  }

  static func bitmapContext(_ data: UnsafeMutableRawPointer?, width: Int, height: Int) -> CGContext? {
    CGContext(
      data: data,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    )
  }

  static func image(from buffer: [UInt8], width: Int, height: Int) -> CGImage? {
    let byteCount = width * height * 4
    guard width > 0, height > 0, buffer.count >= byteCount else {
      return nil
    }
    guard let raw = malloc(byteCount) else {
      return nil
    }
    buffer.withUnsafeBytes { source in
      guard let base = source.baseAddress else { return }
      memcpy(raw, base, byteCount)
    }
    let provider = CGDataProvider(
      dataInfo: nil,
      data: raw,
      size: byteCount,
      releaseData: { _, data, _ in free(UnsafeMutableRawPointer(mutating: data)) }
    )
    guard let provider else {
      free(raw)
      return nil
    }
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }
}
