import AppKit
import CoreGraphics
import Foundation

var failures = 0

func check(_ passed: Bool, _ label: String, _ detail: String) {
  if !passed { failures += 1 }
  print("\(passed ? "PASS" : "FAIL") \(label) -- \(detail)")
}

func makeSource(width: Int = 1600, height: Int = 1000) -> CGImage {
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
  let lines = max(1, height / 38)
  for line in 0..<lines {
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
          y: CGFloat(height) - 50 - CGFloat(line) * 36,
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

struct ComposedCase {
  let label: String
  let overlay: CGSize
  let pixelsPerPoint: CGFloat
  let capture: CGSize
}

let composedCases = [
  ComposedCase(
    label: "overlay 3440x1440 at 1x, capture 1720x1410",
    overlay: CGSize(width: 3440, height: 1440),
    pixelsPerPoint: 1,
    capture: CGSize(width: 1720, height: 1410)
  ),
  ComposedCase(
    label: "overlay 1512x982 at 2x, capture 1720x1410",
    overlay: CGSize(width: 1512, height: 982),
    pixelsPerPoint: 2,
    capture: CGSize(width: 1720, height: 1410)
  ),
  ComposedCase(
    label: "overlay 1440x2560 at 2x, capture 1720x1410",
    overlay: CGSize(width: 1440, height: 2560),
    pixelsPerPoint: 2,
    capture: CGSize(width: 1720, height: 1410)
  ),
]

func percent(_ value: CGFloat) -> String {
  String(format: "%.1f%%", value * 100)
}

@MainActor
func composedDefaultCheck() {
  for testCase in composedCases {
    let source = makeSource(
      width: Int(testCase.capture.width),
      height: Int(testCase.capture.height)
    )
    let scale = AnnotationCanvasView.viewportFitScale(
      viewport: testCase.overlay,
      content: testCase.capture,
      pixelsPerPoint: testCase.pixelsPerPoint
    )
    let magnification = scale * testCase.pixelsPerPoint
    let inset = min(
      (testCase.overlay.width - 48) / testCase.capture.width,
      (testCase.overlay.height - 48) / testCase.capture.height
    )
    let previous = min(1, inset) * testCase.pixelsPerPoint
    let rendered = canvasRender(source: source, scale: magnification)
    let difference = rendered.map { meanAbsoluteDifference($0, source) } ?? .infinity
    let size = rendered.map { "\($0.width)x\($0.height)" } ?? "nil"
    check(
      magnification == 1,
      "default composed preview sits at actual pixels -- \(testCase.label)",
      "device magnification \(percent(magnification)), was \(percent(previous))"
    )
    check(
      difference == 0,
      "default composed preview draws the capture's own pixels -- \(testCase.label)",
      "preview \(size) vs capture \(source.width)x\(source.height), mean |diff| \(String(format: "%.3f", difference))"
    )
  }
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

  composedDefaultCheck()

  print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) CHECK(S) FAILED")
  exit(failures == 0 ? 0 : 1)
}

await run()
