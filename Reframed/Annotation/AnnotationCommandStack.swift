import Foundation

struct AnnotationCommandStack: Sendable {
  private(set) var document: AnnotationDocument
  let maxDepth: Int
  private var past: [AnnotationDocument]
  private var future: [AnnotationDocument]
  private var coalesceKey: String?

  init(document: AnnotationDocument, maxDepth: Int = 50) {
    self.document = document
    self.maxDepth = max(1, maxDepth)
    self.past = []
    self.future = []
    self.coalesceKey = nil
  }

  var canUndo: Bool {
    !past.isEmpty
  }

  var canRedo: Bool {
    !future.isEmpty
  }

  var undoDepth: Int {
    past.count
  }

  var redoDepth: Int {
    future.count
  }

  mutating func commit(key: String? = nil, _ mutate: (inout AnnotationDocument) -> Void) {
    var next = document
    mutate(&next)
    guard next != document else {
      return
    }
    let coalesces = key != nil && key == coalesceKey
    if !coalesces {
      past.append(document)
      trimPast()
    }
    coalesceKey = key
    document = next
    future.removeAll()
  }

  mutating func endCoalescing() {
    coalesceKey = nil
  }

  @discardableResult
  mutating func undo() -> Bool {
    guard let previous = past.popLast() else {
      return false
    }
    future.append(document)
    document = previous
    coalesceKey = nil
    return true
  }

  @discardableResult
  mutating func redo() -> Bool {
    guard let next = future.popLast() else {
      return false
    }
    past.append(document)
    trimPast()
    document = next
    coalesceKey = nil
    return true
  }

  mutating func reset(to document: AnnotationDocument) {
    self.document = document
    past.removeAll()
    future.removeAll()
    coalesceKey = nil
  }

  private mutating func trimPast() {
    if past.count > maxDepth {
      past.removeFirst(past.count - maxDepth)
    }
  }
}
