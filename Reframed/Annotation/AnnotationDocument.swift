import CoreGraphics
import Foundation

struct SourceImageReference: Codable, Sendable, Equatable {
  var identifier: String
  var pixelWidth: Int
  var pixelHeight: Int

  init(identifier: String, pixelWidth: Int, pixelHeight: Int) {
    self.identifier = identifier
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }
}

struct AnnotationDocument: Codable, Sendable, Equatable {
  var source: SourceImageReference
  let pixelSize: CGSize
  private(set) var items: [AnnotationItem]
  var cropRect: CGRect?

  init(
    source: SourceImageReference,
    pixelSize: CGSize,
    items: [AnnotationItem] = [],
    cropRect: CGRect? = nil
  ) {
    self.source = source
    self.pixelSize = pixelSize
    self.items = items
    self.cropRect = cropRect
  }

  var count: Int {
    items.count
  }

  var hasEffects: Bool {
    items.contains { $0.kind == .blur || $0.kind == .pixelate }
  }

  func item(id: UUID) -> AnnotationItem? {
    items.first { $0.id == id }
  }

  func index(of id: UUID) -> Int? {
    items.firstIndex { $0.id == id }
  }

  mutating func append(_ item: AnnotationItem) {
    items.append(item)
  }

  mutating func insert(_ item: AnnotationItem, at index: Int) {
    items.insert(item, at: min(max(index, 0), items.count))
  }

  @discardableResult
  mutating func remove(id: UUID) -> AnnotationItem? {
    guard let index = index(of: id) else {
      return nil
    }
    return items.remove(at: index)
  }

  @discardableResult
  mutating func remove(at index: Int) -> AnnotationItem? {
    guard items.indices.contains(index) else {
      return nil
    }
    return items.remove(at: index)
  }

  @discardableResult
  mutating func replace(id: UUID, with item: AnnotationItem) -> Bool {
    guard let index = index(of: id) else {
      return false
    }
    items[index] = item
    return true
  }

  mutating func move(from source: Int, to destination: Int) {
    guard items.indices.contains(source) else {
      return
    }
    let item = items.remove(at: source)
    items.insert(item, at: min(max(destination, 0), items.count))
  }

  mutating func reorder(_ order: [UUID]) {
    var remaining = items
    var result: [AnnotationItem] = []
    for id in order {
      guard let index = remaining.firstIndex(where: { $0.id == id }) else {
        continue
      }
      result.append(remaining.remove(at: index))
    }
    result.append(contentsOf: remaining)
    items = result
  }

  mutating func bringToFront(id: UUID) {
    guard let index = index(of: id) else {
      return
    }
    move(from: index, to: items.count - 1)
  }
}
