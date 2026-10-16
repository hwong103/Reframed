import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageExportError: LocalizedError {
  case destinationUnavailable(String)
  case writeFailed(String)

  var errorDescription: String? {
    switch self {
    case .destinationUnavailable(let type):
      return "Could not create an image destination for \(type)"
    case .writeFailed(let type):
      return "Could not write the \(type) image"
    }
  }
}

@MainActor
enum ImageExporter {
  @discardableResult
  static func copyToPasteboard(_ image: CGImage, fileURL: URL? = nil) -> Bool {
    guard let png = try? pngData(from: image) else {
      return publish(nil, tiff: tiffData(from: image), fileURL: fileURL)
    }
    return publish(png, tiff: tiffData(from: image), fileURL: fileURL)
  }

  private static func publish(_ png: Data?, tiff: Data?, fileURL: URL?) -> Bool {
    guard png != nil || tiff != nil else { return false }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    var published = false
    if let png {
      published = pasteboard.setData(png, forType: .png) || published
    }
    if let tiff {
      published = pasteboard.setData(tiff, forType: .tiff) || published
    }
    if let fileURL {
      published = pasteboard.setString(fileURL.absoluteString, forType: .fileURL) || published
    }
    return published
  }

  static func writePNG(_ image: CGImage, to url: URL) throws {
    try write(image, to: url, type: .png, quality: nil)
  }

  static func writeJPEG(_ image: CGImage, to url: URL, compression: CGFloat = 0.9) throws {
    try write(image, to: url, type: .jpeg, quality: compression)
  }

  static func pngData(from image: CGImage) throws -> Data {
    try data(from: image, type: .png, quality: nil)
  }

  static func jpegData(from image: CGImage, compression: CGFloat = 0.9) throws -> Data {
    try data(from: image, type: .jpeg, quality: compression)
  }

  static func tiffData(from image: CGImage) -> Data? {
    NSBitmapImageRep(cgImage: image).representation(using: .tiff, properties: [:])
  }

  static func cgImage(fromPNG data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  private static func data(from image: CGImage, type: UTType, quality: CGFloat?) throws -> Data {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
      throw ImageExportError.destinationUnavailable(type.identifier)
    }
    CGImageDestinationAddImage(destination, image, properties(for: quality))
    guard CGImageDestinationFinalize(destination) else {
      throw ImageExportError.writeFailed(type.identifier)
    }
    return output as Data
  }

  private static func write(_ image: CGImage, to url: URL, type: UTType, quality: CGFloat?) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
      throw ImageExportError.destinationUnavailable(type.identifier)
    }
    CGImageDestinationAddImage(destination, image, properties(for: quality))
    guard CGImageDestinationFinalize(destination) else {
      throw ImageExportError.writeFailed(type.identifier)
    }
  }

  private static func properties(for quality: CGFloat?) -> CFDictionary? {
    guard let quality else { return nil }
    return [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
  }
}
