import AppKit
import CoreGraphics

extension AnnotationCanvasView {
  var isDragging: Bool {
    if case .idle = dragState { return false }
    return true
  }

  var isCropping: Bool {
    if case .cropping = dragState { return true }
    return false
  }

  func beginInteraction(at view: CGPoint) {
    if pendingText != nil {
      endTextEditing(commit: true)
    }
    if let handle = handleHit(at: view), let item = model.selectedItem {
      dragState = .resizing(item.id, handle, item.bounds.standardized, item)
      return
    }
    let source = sourcePoint(view)
    if model.tool == .crop {
      dragState = .cropping(source)
      model.setPendingCrop(rectBetween(source, source))
      return
    }
    if model.tool == .text, let stamp = stepStampProvider?() {
      placeStepStamp(stamp, at: source)
      return
    }
    if model.tool == .text {
      beginTextEditing(at: source)
      return
    }
    if let hit = topItem(at: source) {
      dragState = .moving(hit.id, hit, source)
      model.select(hit.id)
      return
    }
    model.select(nil)
    beginCreation(kind: model.tool, at: source)
  }

  func continueInteraction(at view: CGPoint, shiftHeld: Bool = false) {
    let source = sourcePoint(view)
    switch dragState {
    case .idle:
      return
    case .creating(let id):
      updateCreation(id: id, to: source, shiftHeld: shiftHeld)
    case .moving(let id, let original, let origin):
      updateMove(id: id, original: original, origin: origin, to: source)
    case .resizing(let id, let handle, let rect, let original):
      updateResize(id: id, original: original, originalRect: rect, handle: handle, to: source)
    case .cropping(let origin):
      model.setPendingCrop(rectBetween(origin, source))
    }
  }

  func finishInteraction() {
    switch dragState {
    case .creating(let id):
      model.endCoalescing()
      if let item = model.document.item(id: id), isDegenerate(item) {
        model.discardInProgress()
      } else {
        model.select(id)
      }
    case .moving(let id, _, _), .resizing(let id, _, _, _):
      model.endCoalescing()
      model.select(id)
    case .cropping:
      model.endCoalescing()
    case .idle:
      break
    }
    dragState = .idle
    needsDisplay = true
  }

  func cancelDrag() {
    guard isDragging else { return }
    if isCropping {
      model.setPendingCrop(nil)
    } else {
      model.discardInProgress()
    }
    model.endCoalescing()
    dragState = .idle
    needsDisplay = true
  }

  func deleteSelection() {
    guard let id = model.selectionID else { return }
    model.commit { $0.remove(id: id) }
    model.select(nil)
  }

  func confirmPendingCrop() {
    guard model.pendingCrop != nil else { return }
    model.applyPendingCrop()
    needsDisplay = true
  }

  func handleEscape() {
    if model.pendingCrop != nil {
      model.setPendingCrop(nil)
      return
    }
    if pendingText != nil {
      endTextEditing(commit: false)
      return
    }
    if isDragging {
      cancelDrag()
      return
    }
    model.select(nil)
  }

  func beginCreation(kind: AnnotationToolKind, at source: CGPoint) {
    let isFreehand = kind == .pen || kind == .highlighter
    let item = AnnotationItem(
      kind: kind,
      style: model.makeStyle(for: kind),
      start: source,
      end: source,
      points: isFreehand ? [source] : []
    )
    dragState = .creating(item.id)
    model.select(item.id)
    model.commit(key: "create-\(item.id.uuidString)") { $0.append(item) }
  }

  func updateCreation(id: UUID, to source: CGPoint, shiftHeld: Bool = false) {
    guard var item = model.document.item(id: id) else { return }
    switch item.kind {
    case .pen, .highlighter:
      let last = item.points.last ?? item.start
      if hypot(source.x - last.x, source.y - last.y) >= 1 {
        item.points.append(source)
      }
      refreshBounds(&item)
    default:
      item.end = shiftHeld ? constrainedPoint(item.start, source, kind: item.kind) : source
    }
    model.commit(key: "create-\(id.uuidString)") { $0.replace(id: id, with: item) }
  }

  func updateMove(id: UUID, original: AnnotationItem, origin: CGPoint, to source: CGPoint) {
    let dx = source.x - origin.x
    let dy = source.y - origin.y
    var item = original
    item.start = CGPoint(x: original.start.x + dx, y: original.start.y + dy)
    item.end = CGPoint(x: original.end.x + dx, y: original.end.y + dy)
    item.points = original.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    model.commit(key: "move-\(id.uuidString)") { $0.replace(id: id, with: item) }
  }

  func updateResize(
    id: UUID,
    original: AnnotationItem,
    originalRect: CGRect,
    handle: Handle,
    to source: CGPoint
  ) {
    let target = resized(originalRect, handle: handle, to: source)
    let item = transformed(original, from: originalRect, to: target)
    model.commit(key: "resize-\(id.uuidString)") { $0.replace(id: id, with: item) }
  }
}
