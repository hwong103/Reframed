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
  static func recognize(in image: CGImage) throws -> OCRResult {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    return OCRResult(lines: try lines(of: request, in: image))
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
    let candidates = observations.compactMap { observation -> (CGRect, String)? in
      guard let text = observation.topCandidates(1).first?.string else { return nil }
      return (observation.boundingBox, text)
    }
    let ordered = candidates.sorted { lhs, rhs in
      if abs(lhs.0.midY - rhs.0.midY) > 0.02 {
        return lhs.0.midY > rhs.0.midY
      }
      return lhs.0.minX < rhs.0.minX
    }
    return ordered.map(\.1)
  }
}
