import AppKit
import CoreGraphics
import Foundation

struct RecentCaptureData: Codable, Identifiable {
  var id: String
  var date: Date
  var filename: String
  var width: Int
  var height: Int
}

@MainActor
protocol RecentCapturePersisting: AnyObject {
  var recentCaptures: [RecentCaptureData] { get set }
  @discardableResult
  func commitCaptureList(_ items: [RecentCaptureData]) -> Bool
}

extension RecentCapturePersisting {
  @discardableResult
  func commitCaptureList(_ items: [RecentCaptureData]) -> Bool {
    recentCaptures = items
    return true
  }
}

@MainActor
final class RecentCaptureStore {
  static let limit = 20
  static let defaultByteLimit = 200 * 1024 * 1024
  static let folderName = "RecentCaptures"

  static let shared = RecentCaptureStore(
    persistence: StateService.shared,
    directory: defaultDirectory()
  )

  static func defaultDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    let root = base ?? FileManager.default.homeDirectoryForCurrentUser
    return
      root
      .appendingPathComponent("Reframed", isDirectory: true)
      .appendingPathComponent(folderName, isDirectory: true)
  }

  private let persistence: RecentCapturePersisting
  private let directory: URL
  private let byteLimit: Int

  init(
    persistence: RecentCapturePersisting,
    directory: URL,
    byteLimit: Int? = nil
  ) {
    self.persistence = persistence
    self.directory = directory
    self.byteLimit = byteLimit ?? Self.defaultByteLimit
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    pruneMissingFiles()
    removeOrphans()
  }

  var captures: [RecentCaptureData] {
    persistence.recentCaptures
  }

  func fileURL(for id: String) -> URL {
    directory.appendingPathComponent("\(id).png")
  }

  func image(for item: RecentCaptureData) -> CGImage? {
    guard let data = try? Data(contentsOf: fileURL(for: item.id)) else { return nil }
    return ImageExporter.cgImage(fromPNG: data)
  }

  func record(image: CGImage, filename: String, date: Date = Date()) {
    guard let png = try? ImageExporter.pngData(from: image) else { return }
    let item = RecentCaptureData(
      id: UUID().uuidString,
      date: date,
      filename: filename,
      width: image.width,
      height: image.height
    )
    guard (try? png.write(to: fileURL(for: item.id), options: .atomic)) != nil else { return }
    var items = persistence.recentCaptures
    items.insert(item, at: 0)
    var evicted: [RecentCaptureData] = []
    while items.count > 1, items.count > Self.limit || byteSize(of: items) > byteLimit {
      evicted.append(items.removeLast())
    }
    guard persistence.commitCaptureList(items) else { return }
    removeFiles(for: evicted)
  }

  @discardableResult
  func copyToClipboard(_ item: RecentCaptureData) -> Bool {
    guard let image = image(for: item) else { return false }
    return ImageExporter.copyToPasteboard(image, fileURL: clipboardURL(for: item))
  }

  func reveal(_ item: RecentCaptureData) {
    let url = fileURL(for: item.id)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func clear() {
    let cleared = persistence.recentCaptures
    guard persistence.commitCaptureList([]) else { return }
    removeFiles(for: cleared)
  }

  private func pruneMissingFiles() {
    let stored = persistence.recentCaptures
    let survivors = stored.filter { FileManager.default.fileExists(atPath: fileURL(for: $0.id).path) }
    guard survivors.count != stored.count else { return }
    persistence.recentCaptures = survivors
  }

  private func removeFiles(for items: [RecentCaptureData]) {
    for item in items {
      try? FileManager.default.removeItem(at: fileURL(for: item.id))
    }
  }

  private func clipboardURL(for item: RecentCaptureData) -> URL? {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("Reframed-\(item.id).png")
    guard (try? FileManager.default.copyItem(at: fileURL(for: item.id), to: url)) != nil else {
      return nil
    }
    return url
  }

  private func removeOrphans() {
    let known = Set(persistence.recentCaptures.map { "\($0.id).png" })
    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    for name in files where name.hasSuffix(".png") && !known.contains(name) {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
  }

  private func byteSize(of items: [RecentCaptureData]) -> Int {
    items.reduce(0) { total, item in
      let values = try? fileURL(for: item.id).resourceValues(forKeys: [.fileSizeKey])
      return total + (values?.fileSize ?? 0)
    }
  }
}
