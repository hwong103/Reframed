import AppKit
import CoreGraphics

@MainActor
final class AnnotationCanvasView: NSView {
  struct Layout {
    let scale: CGFloat
    let origin: CGPoint
  }

  struct PendingText {
    let anchor: CGPoint
  }

  struct DragComposition {
    let itemID: UUID
    let index: Int
    let others: [AnnotationItem]
    let crop: CGRect?
    let prefix: [UInt8]
    let suffix: [AnnotationItem]
    let width: Int
    let height: Int
  }

  enum Handle: Int, CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
  }

  enum DragState {
    case idle
    case creating(UUID)
    case moving(UUID, AnnotationItem, CGPoint)
    case resizing(UUID, Handle, CGRect, AnnotationItem)
    case cropping(CGPoint)
  }

  let model: AnnotationEditorModel
  let textEditor = NSTextView()
  let textScrollView = NSScrollView()
  var textEditorOrigin: CGPoint = .zero
  var canvasBackground = NSColor(white: 0.5, alpha: 1)
  let handleSize: CGFloat = 8
  let handleHitRadius: CGFloat = 7
  let tolerance: CGFloat = 8
  var dragState: DragState = .idle
  var pendingText: PendingText?
  var isInline = false
  var stepStampProvider: (() -> String?)?
  var explicitLayout: Layout?
  var beautifyStyle: BeautifyStyle = .off
  var beautifyScale: CGFloat = 1
  var dragComposition: DragComposition?

  var draggingItemID: UUID? {
    switch dragState {
    case .creating(let id), .moving(let id, _, _), .resizing(let id, _, _, _):
      return id
    default:
      return nil
    }
  }

  init(model: AnnotationEditorModel) {
    self.model = model
    super.init(frame: .zero)
    wantsLayer = true
    model.changeHandler = { [weak self] in
      self?.needsDisplay = true
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var acceptsFirstResponder: Bool { true }
  override var isOpaque: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.setFillColor(canvasBackground.cgColor)
    context.fill(bounds)
    drawRenderedImage(in: context)
    drawSelection(in: context)
    drawPendingCrop(in: context)
    drawViewportHUD(in: context)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    beginInteraction(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseDragged(with event: NSEvent) {
    continueInteraction(
      at: convert(event.locationInWindow, from: nil),
      shiftHeld: event.modifierFlags.contains(.shift)
    )
  }

  override func mouseUp(with event: NSEvent) {
    finishInteraction()
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 51, 117:
      deleteSelection()
    case 36, 76:
      confirmPendingCrop()
    case 53:
      handleEscape()
    default:
      super.keyDown(with: event)
    }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard pendingText == nil else {
      return super.performKeyEquivalent(with: event)
    }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" else {
      return super.performKeyEquivalent(with: event)
    }
    if flags.contains(.shift) {
      model.redo()
    } else {
      model.undo()
    }
    return true
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    syncContentsScale()
    needsDisplay = true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    syncContentsScale()
  }

  func syncContentsScale() {
    guard let scale = window?.backingScaleFactor, scale > 0 else { return }
    guard layer?.contentsScale != scale else { return }
    layer?.contentsScale = scale
    needsDisplay = true
  }
}
