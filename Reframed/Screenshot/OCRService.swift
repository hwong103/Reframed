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
  private static let fallbackLanguages = ["en-US"]
  private static let accurateRetryPixelLimit = 4_000_000

  static func recognize(in image: CGImage) throws -> OCRResult {
    let fast = try pass(in: image, level: .fast, correctsLanguage: false)
    if !fast.lines.isEmpty {
      return OCRResult(lines: fast.lines)
    }
    guard fast.observations > 0, image.width * image.height <= accurateRetryPixelLimit else {
      return OCRResult(lines: [])
    }
    let accurate = try pass(in: image, level: .accurate, correctsLanguage: true)
    return OCRResult(lines: accurate.lines)
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

  private struct Pass {
    let lines: [String]
    let observations: Int
  }

  private static func pass(
    in image: CGImage,
    level: VNRequestTextRecognitionLevel,
    correctsLanguage: Bool
  ) throws -> Pass {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.usesLanguageCorrection = correctsLanguage
    request.automaticallyDetectsLanguage = false
    request.recognitionLanguages = recognitionLanguages(level: level)

    let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw OCRError.recognitionFailed(error.localizedDescription)
    }
    let results = request.results ?? []
    return Pass(lines: readingOrderedLines(from: results), observations: results.count)
  }

  private static func recognitionLanguages(level: VNRequestTextRecognitionLevel) -> [String] {
    let supported = supportedLanguages(level: level)
    var matches: [String] = []
    for preferred in Locale.preferredLanguages {
      if supported.contains(preferred) {
        matches.append(preferred)
      } else if let match = supported.first(where: { sharesLanguage(with: $0, preferred) }) {
        matches.append(match)
      }
    }
    let unique = matches.reduce(into: [String]()) { result, language in
      if !result.contains(language) {
        result.append(language)
      }
    }
    return unique.isEmpty ? fallbackLanguages : Array(unique.prefix(3))
  }

  private static func supportedLanguages(level: VNRequestTextRecognitionLevel) -> [String] {
    let probe = VNRecognizeTextRequest()
    probe.recognitionLevel = level
    return (try? probe.supportedRecognitionLanguages()) ?? []
  }

  private static func sharesLanguage(with identifier: String, _ preferred: String) -> Bool {
    guard let supported = Locale(identifier: identifier).language.languageCode?.identifier else {
      return false
    }
    return supported == Locale(identifier: preferred).language.languageCode?.identifier
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
