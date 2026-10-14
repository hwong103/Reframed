import AppKit
import CoreGraphics
import Foundation

var failures = 0

func check(_ passed: Bool, _ label: String, _ detail: String) {
  if !passed { failures += 1 }
  print("\(passed ? "PASS" : "FAIL") \(label) -- \(detail)")
}

func makeSource() -> CGImage {
  let width = 1600
  let height = 1000
  let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let body: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17),
    .foregroundColor: NSColor.black,
  ]
  for line in 0..<26 {
    let string = NSAttributedString(
      string: "Invoice 4092 line \(line) total $18,404.22 due 14 October",
      attributes: body
    )
    let size = string.size()
    let holder = NSImage(
      size: NSSize(width: Int(size.width.rounded(.up)) + 4, height: Int(size.height.rounded(.up)) + 4)
    )
    holder.lockFocus()
    string.draw(at: .zero)
    holder.unlockFocus()
    if let strip = holder.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      context.draw(
        strip,
        in: CGRect(
          x: 30,
          y: 950 - CGFloat(line) * 36,
          width: CGFloat(strip.width),
          height: CGFloat(strip.height)
        )
      )
    }
  }
  return context.makeImage()!
}

func pixels(_ image: CGImage) -> [UInt8] {
  var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
  buffer.withUnsafeMutableBytes { raw in
    let context = CGContext(
      data: raw.baseAddress,
      width: image.width,
      height: image.height,
      bitsPerComponent: 8,
      bytesPerRow: image.width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setBlendMode(.copy)
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  }
  return buffer
}

func meanAbsoluteDifference(_ lhs: CGImage, _ rhs: CGImage) -> Double {
  guard lhs.width == rhs.width, lhs.height == rhs.height else { return .infinity }
  let left = pixels(lhs)
  let right = pixels(rhs)
  var total = 0.0
  for index in stride(from: 0, to: left.count, by: 4) {
    total += abs(Double(left[index]) - Double(right[index]))
  }
  return total / Double(lhs.width * lhs.height)
}

func directRender(source: CGImage, scale: CGFloat, quality: CGInterpolationQuality) -> CGImage? {
  let width = Int((CGFloat(source.width) * scale).rounded())
  let height = Int((CGFloat(source.height) * scale).rounded())
  guard let context = AnnotationRenderer.bitmapContext(nil, width: width, height: height) else {
    return nil
  }
  context.interpolationQuality = quality
  context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
  return context.makeImage()
}

@MainActor
func canvasRender(source: CGImage, scale: CGFloat) -> CGImage? {
  let reference = SourceImageReference(
    identifier: "preview-scale",
    pixelWidth: source.width,
    pixelHeight: source.height
  )
  let model = AnnotationEditorModel(image: source, reference: reference)
  let canvas = AnnotationCanvasView(model: model)
  canvas.beautifyStyle = .off
  canvas.beautifyScale = 1
  canvas.explicitLayout = AnnotationCanvasView.Layout(scale: scale, origin: .zero)
  let width = Int((CGFloat(source.width) * scale).rounded())
  let height = Int((CGFloat(source.height) * scale).rounded())
  guard let context = AnnotationRenderer.bitmapContext(nil, width: width, height: height) else {
    return nil
  }
  canvas.drawRenderedImage(in: context)
  return context.makeImage()
}

@MainActor
func run() {
  let source = makeSource()

  for scale in [CGFloat(1), CGFloat(0.5), CGFloat(0.72), CGFloat(2)] {
    guard
      let canvas = canvasRender(source: source, scale: scale),
      let nearest = directRender(source: source, scale: scale, quality: .none),
      let area = directRender(source: source, scale: scale, quality: .high)
    else {
      check(false, "render at scale \(scale)", "returned nil")
      continue
    }
    let toNearest = meanAbsoluteDifference(canvas, nearest)
    let toArea = meanAbsoluteDifference(canvas, area)
    let label = String(format: "preview scale %.2f", scale)
    if scale < 1 {
      check(
        toArea == 0,
        "\(label) downscales with an area filter",
        String(format: "diff from area %.3f, from nearest %.3f", toArea, toNearest)
      )
    } else {
      check(
        toNearest == 0,
        "\(label) keeps pixel-exact sampling when not downscaling",
        String(format: "diff from nearest %.3f, from area %.3f", toNearest, toArea)
      )
    }
  }

  print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) CHECK(S) FAILED")
  exit(failures == 0 ? 0 : 1)
}

await run()
