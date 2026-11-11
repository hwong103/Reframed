import AppKit
import CoreGraphics

let clock = ContinuousClock()

func milliseconds(_ duration: Duration) -> Double {
  let components = duration.components
  return Double(components.seconds) * 1_000
    + Double(components.attoseconds) / 1_000_000_000_000_000
}

guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 800,
    pixelsHigh: 240,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  fputs("FAIL could not create OCR fixture\n", stderr)
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: 800, height: 240).fill()
NSString(string: "Reframed text snip").draw(
  at: NSPoint(x: 40, y: 80),
  withAttributes: [
    .font: NSFont.systemFont(ofSize: 64, weight: .medium),
    .foregroundColor: NSColor.black,
  ]
)
NSGraphicsContext.restoreGraphicsState()

guard let image = bitmap.cgImage else {
  fputs("FAIL could not render OCR fixture\n", stderr)
  exit(1)
}

let warmUpStart = clock.now
let warmUpTask = MainActor.assumeIsolated { OCRService.warmUp() }
let warmUpComplete = DispatchSemaphore(value: 0)
Task.detached {
  await warmUpTask.value
  warmUpComplete.signal()
}
warmUpComplete.wait()
let warmUpDuration = clock.now - warmUpStart

do {
  let firstRecognitionStart = clock.now
  let actual = try OCRService.recognize(in: image)
  let firstRecognitionDuration = clock.now - firstRecognitionStart
  guard actual.text.localizedCaseInsensitiveContains("Reframed") else {
    fputs("FAIL OCR returned \(actual.text.debugDescription)\n", stderr)
    exit(1)
  }
  print(
    String(
      format: "INFO first call %.1f ms, first real recognition %.1f ms",
      milliseconds(warmUpDuration),
      milliseconds(firstRecognitionDuration)
    )
  )

  let result = try OCRService.recognize(in: image) { _, level in
    guard level == .fast else {
      throw NSError(
        domain: "TextRecognition.CRImageReaderError",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "The operation couldn't be completed. (TextRecognition.CRImageReaderError error 1.)"]
      )
    }
    return try OCRService.recognitionLines(in: image, level: level)
  }
  guard result.text == "Reframed text snip" else {
    fputs("FAIL OCR returned \(result.text.debugDescription)\n", stderr)
    exit(1)
  }
  print("PASS OCR completed and retried with fast recognition after accurate model failure")
} catch {
  fputs("FAIL \(error.localizedDescription)\n", stderr)
  exit(1)
}
