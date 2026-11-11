import AppKit
import CoreGraphics
import Foundation
import Vision

enum OCRError: LocalizedError {
  case invalidRegion
  case recognitionFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidRegion:
      return "The text region is empty"
    case .recognitionFailed(let message):
      return "Text recognition failed: \(message)"
    }
  }
}

struct OCRResult: Sendable, Equatable {
  let lines: [String]

  var text: String {
    lines.joined(separator: "\n")
  }

  var characterCount: Int {
    text.count
  }
}

enum OCRService {
  typealias RecognitionAttempt = (CGImage, VNRequestTextRecognitionLevel) throws -> [String]

  @MainActor private static var warmUpTask: Task<Void, Never>?

  @discardableResult
  @MainActor
  static func warmUp() -> Task<Void, Never> {
    if let warmUpTask {
      return warmUpTask
    }
    let task: Task<Void, Never>
    if let image = sampleImage() {
      task = Task.detached(priority: .userInitiated) {
        _ = try? recognize(in: image)
      }
    } else {
      task = Task {}
    }
    warmUpTask = task
    return task
  }

  @MainActor
  static func waitUntilWarm() async {
    await warmUp().value
  }

  static func recognize(in image: CGImage) throws -> OCRResult {
    try recognize(in: image, using: recognitionLines)
  }

  static func recognize(in image: CGImage, using attempt: RecognitionAttempt) throws -> OCRResult {
    do {
      return OCRResult(lines: try attempt(image, .accurate))
    } catch {
      return OCRResult(lines: try attempt(image, .fast))
    }
  }

  static func recognitionLines(
    in image: CGImage,
    level: VNRequestTextRecognitionLevel
  ) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    return try lines(of: request, in: image)
  }

  static func recognize(in image: CGImage, region: CGRect) throws -> OCRResult {
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let clipped = region.standardized.integral.intersection(bounds)
    guard clipped.width >= 1, clipped.height >= 1 else {
      throw OCRError.invalidRegion
    }
    guard let cropped = image.cropping(to: clipped) else {
      throw OCRError.invalidRegion
    }
    return try recognize(in: cropped)
  }

  private static func lines(of request: VNRecognizeTextRequest, in image: CGImage) throws -> [String] {
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw OCRError.recognitionFailed(error.localizedDescription)
    }
    return readingOrderedLines(from: request.results ?? [])
  }

  private static func readingOrderedLines(from observations: [VNRecognizedTextObservation]) -> [String] {
    let candidates = observations.compactMap { observation -> Candidate? in
      guard let text = observation.topCandidates(1).first?.string else { return nil }
      return (rect: observation.boundingBox, text: text)
    }
    return orderedLines(from: candidates)
  }

  @MainActor
  private static func sampleImage() -> CGImage? {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 320,
        pixelsHigh: 64,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else {
      return nil
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 320, height: 64).fill()
    NSString(string: "Text Snip 123").draw(
      at: NSPoint(x: 16, y: 16),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .medium),
        .foregroundColor: NSColor.black,
      ]
    )
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.cgImage
  }
}
