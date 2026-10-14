import AppKit
import CoreGraphics
import Foundation

let sourceWidth = 400
let sourceHeight = 300
var failures = 0

func check(_ passed: Bool, _ label: String, _ detail: String) {
  if !passed { failures += 1 }
  print("\(passed ? "PASS" : "FAIL") \(label) -- \(detail)")
}

func makeSource() -> CGImage {
  let context = CGContext(
    data: nil,
    width: sourceWidth,
    height: sourceHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
  context.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 40, y: 60, width: 180, height: 90))
  context.setFillColor(CGColor(srgbRed: 0.9, green: 0.5, blue: 0.1, alpha: 1))
  context.fill(CGRect(x: 240, y: 150, width: 120, height: 120))
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24),
    .foregroundColor: NSColor.black,
  ]
  let holder = NSImage(size: NSSize(width: 340, height: 32))
  holder.lockFocus()
  NSAttributedString(string: "Invoice 4092 total $18,404.22", attributes: attributes).draw(at: .zero)
  holder.unlockFocus()
  if let line = holder.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    context.draw(line, in: CGRect(x: 20, y: 20, width: 340, height: 32))
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
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  }
  return buffer
}

struct Comparison {
  var differing = 0
  var maxDelta = 0
  var total = 0
  var sizeMatched = false
  var minX = 0
  var minY = 0
  var maxX = 0
  var maxY = 0
}

@MainActor
func compare(source: CGImage, style: BeautifyStyle, density: CGFloat) -> Comparison? {
  var result = Comparison()
  guard let export = AnnotationRenderer.beautified(source, style: style, scale: density) else {
    return nil
  }
  let reference = SourceImageReference(
    identifier: "beautify-preview-parity",
    pixelWidth: source.width,
    pixelHeight: source.height
  )
  let model = AnnotationEditorModel(image: source, reference: reference)
  let canvas = AnnotationCanvasView(model: model)
  canvas.beautifyStyle = style
  canvas.beautifyScale = density
  canvas.explicitLayout = AnnotationCanvasView.Layout(scale: 1, origin: .zero)
  guard let context = AnnotationRenderer.bitmapContext(nil, width: export.width, height: export.height) else {
    return nil
  }
  canvas.drawRenderedImage(in: context)
  guard let preview = context.makeImage() else { return nil }
  guard preview.width == export.width, preview.height == export.height else { return nil }
  result.sizeMatched = true
  result.total = export.width * export.height
  let exported = pixels(export)
  let rendered = pixels(preview)
  result.minX = export.width
  result.minY = export.height
  result.maxX = -1
  result.maxY = -1
  for y in 0..<export.height {
    for x in 0..<export.width {
      let index = (y * export.width + x) * 4
      var delta = 0
      for channel in 0..<4 {
        delta = max(delta, abs(Int(exported[index + channel]) - Int(rendered[index + channel])))
      }
      if delta > 0 {
        result.differing += 1
        result.maxDelta = max(result.maxDelta, delta)
        result.minX = min(result.minX, x)
        result.minY = min(result.minY, y)
        result.maxX = max(result.maxX, x)
        result.maxY = max(result.maxY, y)
      }
    }
  }
  return result
}

@MainActor
func run() async {
  let source = makeSource()

  guard let off = AnnotationRenderer.beautified(source, style: .off, scale: 2) else {
    print("FAIL beautified(.off) returned nil")
    exit(1)
  }
  check(pixels(off) == pixels(source), "style off is a byte-for-byte no-op", "\(off.width)x\(off.height)")

  let solid = CodableColor(r: 0.9, g: 0.2, b: 0.2)
  let cases: [(String, BeautifyStyle, CGFloat)] = [
    ("standard @1x", .standard, 1),
    ("standard @2x", .standard, 2),
    ("standard @3x", .standard, 3),
    ("padding only @2x", BeautifyStyle(padding: 32), 2),
    ("corners only @2x", BeautifyStyle(cornerRadius: 10), 2),
    ("shadow, no padding @2x", BeautifyStyle(shadowOpacity: 0.4, shadowRadius: 10, shadowOffset: 6), 2),
    (
      "solid background @2x",
      BeautifyStyle(
        padding: 20,
        cornerRadius: 8,
        shadowOpacity: 0.4,
        shadowRadius: 10,
        shadowOffset: 6,
        background: .solidColor(solid)
      ),
      2
    ),
    (
      "gradient background @2x",
      BeautifyStyle(
        padding: 36,
        cornerRadius: 12,
        shadowOpacity: 0.25,
        shadowRadius: 20,
        shadowOffset: 10,
        background: .gradient(1)
      ),
      2
    ),
    ("standard @1.5x", .standard, 1.5),
  ]

  for (label, style, density) in cases {
    guard let result = compare(source: source, style: style, density: density) else {
      check(false, "preview matches export: \(label)", "renderer or preview returned nil")
      continue
    }
    let ratio = Double(result.differing) / Double(max(result.total, 1)) * 100
    check(
      result.sizeMatched && result.differing == 0,
      "preview matches export: \(label)",
      "\(result.differing)/\(result.total) px differ (\(String(format: "%.3f", ratio))%) maxDelta \(result.maxDelta)"
    )
    if result.differing > 0 {
      print("     differing region: x \(result.minX)...\(result.maxX)  y \(result.minY)...\(result.maxY)")
    }
  }

  print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) CHECK(S) FAILED")
  exit(failures == 0 ? 0 : 1)
}

await run()
