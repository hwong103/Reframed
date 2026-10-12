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
  static func copyToPasteboard(_ image: CGImage, fileURL: URL? = nil) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    if let png = try? pngData(from: image) {
      pasteboard.setData(png, forType: .png)
    }
    if let tiff = tiffData(from: image) {
      pasteboard.setData(tiff, forType: .tiff)
    }
    if let fileURL {
      pasteboard.setString(fileURL.absoluteString, forType: .fileURL)
    }
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
