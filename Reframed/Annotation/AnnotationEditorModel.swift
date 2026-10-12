import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AnnotationEditorModel {
  let image: CGImage
  var tool: AnnotationToolKind = .arrow
  var strokeColor: CodableColor = AnnotationPresets.defaultColor
  var strokeWidth: CGFloat = AnnotationPresets.defaultStrokeWidth
  var fontSize: CGFloat = AnnotationPresets.defaultFontSize
  var blurRadius: CGFloat = AnnotationPresets.defaultBlurRadius
  private(set) var stack: AnnotationCommandStack
  private(set) var selectionID: UUID?
  private(set) var pendingCrop: CGRect?
  @ObservationIgnored var changeHandler: (() -> Void)?

  init(image: CGImage, reference: SourceImageReference) {
    self.image = image
    self.stack = AnnotationCommandStack(
      document: AnnotationDocument(
        source: reference,
        pixelSize: CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
      )
    )
  }

  var document: AnnotationDocument { stack.document }
  var pixelSize: CGSize { stack.document.pixelSize }
  var outputSize: CGSize { AnnotationRenderer.outputSize(for: stack.document) }
  var canUndo: Bool { stack.canUndo }
  var canRedo: Bool { stack.canRedo }
  var selectedItem: AnnotationItem? { selectionID.flatMap { stack.document.item(id: $0) } }

  func makeStyle(for kind: AnnotationToolKind) -> AnnotationStyle {
    switch kind {
    case .highlighter:
      return AnnotationStyle(
        strokeColor: strokeColor,
        strokeWidth: max(strokeWidth, AnnotationPresets.defaultHighlighterWidth),
        opacity: AnnotationPresets.defaultHighlighterOpacity
      )
    case .text:
      return AnnotationStyle(strokeColor: strokeColor, fontSize: fontSize)
    case .blur:
      return AnnotationStyle(strokeColor: strokeColor, blurRadius: blurRadius)
    case .pixelate:
      return AnnotationStyle(strokeColor: strokeColor, blurRadius: max(4, blurRadius))
    case .arrow, .rectangle, .ellipse, .line, .pen, .crop:
      return AnnotationStyle(strokeColor: strokeColor, strokeWidth: strokeWidth)
    }
  }

  func commit(key: String? = nil, _ mutate: (inout AnnotationDocument) -> Void) {
    stack.commit(key: key, mutate)
    changeHandler?()
  }

  func endCoalescing() {
    stack.endCoalescing()
  }

  func undo() {
    guard stack.undo() else { return }
    reconcileSelection()
    changeHandler?()
  }

  func redo() {
    guard stack.redo() else { return }
    reconcileSelection()
    changeHandler?()
  }

  func discardInProgress() {
    guard stack.undo() else { return }
    reconcileSelection()
    changeHandler?()
  }

  func select(_ id: UUID?) {
    guard selectionID != id else { return }
    selectionID = id
    stack.endCoalescing()
    changeHandler?()
  }

  func setTool(_ kind: AnnotationToolKind) {
    tool = kind
    guard kind != .crop, pendingCrop != nil else { return }
    pendingCrop = nil
    changeHandler?()
  }

  func setPendingCrop(_ rect: CGRect?) {
    pendingCrop = rect
    changeHandler?()
  }

  func applyPendingCrop() {
    guard let pending = pendingCrop else { return }
    let clamped = pending.standardized.integral
    pendingCrop = nil
    guard clamped.width >= 1, clamped.height >= 1 else {
      changeHandler?()
      return
    }
    commit { $0.cropRect = clamped }
  }

  func setStrokeColor(_ color: CodableColor) {
    strokeColor = color
    restyleSelection { $0.strokeColor = color }
  }

  func setStrokeWidth(_ width: CGFloat) {
    strokeWidth = width
    restyleSelection { $0.strokeWidth = width }
  }

  func setFontSize(_ size: CGFloat) {
    fontSize = size
    restyleSelection { $0.fontSize = size }
  }

  func setBlurRadius(_ radius: CGFloat) {
    blurRadius = radius
    restyleSelection { $0.blurRadius = radius }
  }

  func renderedImage() -> CGImage? {
    AnnotationRenderer.makeImage(stack.document, image: image)
  }

  private func reconcileSelection() {
    guard let id = selectionID else { return }
    guard stack.document.item(id: id) == nil else { return }
    selectionID = nil
  }

  private func restyleSelection(_ transform: (inout AnnotationStyle) -> Void) {
    guard let id = selectionID, var item = stack.document.item(id: id) else { return }
    transform(&item.style)
    commit(key: "style-\(id.uuidString)") { $0.replace(id: id, with: item) }
  }
}
