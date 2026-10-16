import Foundation

@MainActor
enum ScreenshotNaming {
  static let defaultPrefix = "Screenshot"
  static let fileExtension = "png"
  static let prefixDefaultsKey = "screenshotNamePrefix"

  static var prefix: String {
    guard let stored = UserDefaults.standard.string(forKey: prefixDefaultsKey) else {
      return defaultPrefix
    }
    let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? defaultPrefix : trimmed
  }

  static var storedPrefix: String {
    get { UserDefaults.standard.string(forKey: prefixDefaultsKey) ?? defaultPrefix }
    set { UserDefaults.standard.set(newValue, forKey: prefixDefaultsKey) }
  }

  static func resetPrefix() {
    UserDefaults.standard.removeObject(forKey: prefixDefaultsKey)
  }

  static func previewName(prefix: String? = nil) -> String {
    "\(baseName(prefix: prefix)).\(fileExtension)"
  }

  static func fileSafe(_ raw: String) -> String {
    let separators = CharacterSet(charactersIn: "/\\:\u{0000}")
    let cleaned =
      raw
      .components(separatedBy: separators)
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? defaultPrefix : cleaned
  }

  static func baseName(date: Date = Date(), prefix: String? = nil) -> String {
    "\(resolvedPrefix(prefix))-\(formatTimestamp(date))"
  }

  static func destinationURL(date: Date = Date(), prefix: String? = nil, in directory: URL? = nil) -> URL {
    let targetDirectory = directory ?? FileManager.default.defaultSaveDirectory()
    return uniqueURL(
      in: targetDirectory,
      baseName: baseName(date: date, prefix: prefix),
      fileExtension: fileExtension
    )
  }

  static func uniqueURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
    var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
    var suffix = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = directory.appendingPathComponent("\(baseName)-\(suffix).\(fileExtension)")
      suffix += 1
    }
    return candidate
  }

  private static func resolvedPrefix(_ override: String?) -> String {
    fileSafe(override ?? prefix)
  }
}
