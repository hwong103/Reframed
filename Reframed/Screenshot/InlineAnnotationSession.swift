import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class InlineAnnotationSession {
  let state = CaptureAnnotationState()
  let displaySize: CGSize
  private let image: CGImage
  private let reference: SourceImageReference
  let handlers: SelectionAnnotationHandlers
  var selection: SelectionRect
  var localRect: CGRect
  lazy var model = AnnotationEditorModel(image: image, reference: reference)
  lazy var canvas: AnnotationCanvasView = {
    let view = AnnotationCanvasView(model: model)
    view.isInline = true
    return view
  }()
  private lazy var clip: NSView = {
    let container = NSView(frame: CGRect(origin: .zero, size: displaySize))
    container.wantsLayer = true
    container.layer?.masksToBounds = true
    container.addSubview(canvas)
    return container
  }()
  private lazy var chrome = SelectionChromeView()
  lazy var badgeHost: NSHostingView<CaptureDimensionBadge> = {
    let host = NSHostingView(rootView: CaptureDimensionBadge(state: state))
    host.sizingOptions = [.intrinsicContentSize]
    return host
  }()
  lazy var closeHost: NSHostingView<CaptureCloseButton> = {
    let host = NSHostingView(rootView: CaptureCloseButton(action: makeCloseAction()))
    host.sizingOptions = [.intrinsicContentSize]
    return host
  }()
  lazy var toolbarHost: NSHostingView<CaptureAnnotationToolbarView> = {
    let host = NSHostingView(rootView: CaptureAnnotationToolbarView(state: state, actions: makeActions()))
    host.sizingOptions = [.intrinsicContentSize]
    return host
  }()

  var isSelectionToolActive: Bool { state.tool == .selection }
  var isAspectLocked: Bool { state.aspectLocked }

  init(
    image: CGImage,
    selection: SelectionRect,
    localRect: CGRect,
    displaySize: CGSize,
    handlers: SelectionAnnotationHandlers
  ) {
    self.image = image
    self.selection = selection
    self.localRect = localRect
    self.displaySize = displaySize
    self.handlers = handlers
    self.reference = SourceImageReference(
      identifier: "inline-\(selection.displayID)-\(Int(selection.rect.minX))-\(Int(selection.rect.minY))",
      pixelWidth: image.width,
      pixelHeight: image.height
    )
  }

  func install(in parent: NSView) {
    parent.addSubview(clip)
    parent.addSubview(chrome)
    parent.addSubview(badgeHost)
    parent.addSubview(closeHost)
    parent.addSubview(toolbarHost)
    model.changeHandler = { [weak self] in
      self?.canvas.needsDisplay = true
      self?.refreshState()
    }
    selectTool(state.tool)
    applyStyle()
    refreshState()
  }

  func update(bounds: CGRect, localRect: CGRect, selection: SelectionRect) {
    self.localRect = localRect
    self.selection = selection
    state.pointSize = localRect.size
    layout(bounds: bounds)
  }

  func selectTool(_ tool: CaptureAnnotationTool) {
    state.tool = tool
    if let kind = tool.annotationKind {
      model.setTool(kind)
    }
    canvas.stepStampProvider = tool == .step ? { [weak self] in self?.state.nextStepLabel() } : nil
  }

  func applyStyle() {
    let color = state.selectedColor
    model.setStrokeColor(CodableColor(r: color.r, g: color.g, b: color.b, a: state.opacity))
    model.setStrokeWidth(state.thickness)
    model.setFontSize(state.size)
    model.setBlurRadius(max(4, state.size))
  }

  func refreshState() {
    state.canUndo = model.canUndo
    state.canRedo = model.canRedo
    state.hasSelection = model.selectionID != nil
  }

  func handleKey(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

    if flags.contains(.command) {
      switch key {
      case "s":
        flags.contains(.shift) ? saveAndCopy() : save()
        return true
      case "z":
        flags.contains(.shift) ? redo() : undo()
        return true
      default:
        return false
      }
    }

    guard flags.isEmpty else { return false }

    switch event.keyCode {
    case 53:
      cancel()
      return true
    case 36, 49, 76:
      copy()
      return true
    case 51, 117:
      deleteSelected()
      return true
    default:
      break
    }

    if let tool = CaptureAnnotationTool.tool(forKey: key) {
      selectTool(tool)
      return true
    }

    switch key {
    case "o":
      captureText()
    case "t":
      pin()
    case "w":
      openInWindow()
    case "p":
      openInPreview()
    default:
      return key == "s"
    }
    return true
  }

  func cancel() {
    handlers.cancel()
  }

  private func layout(bounds: CGRect) {
    clip.frame = localRect
    canvas.frame = CGRect(origin: CGPoint(x: -localRect.minX, y: -localRect.minY), size: displaySize)
    chrome.frame = bounds
    chrome.selectionRect = localRect
    chrome.needsDisplay = true
    let badgeSize = badgeHost.fittingSize
    layoutBadge(badgeSize: badgeSize, bounds: bounds)
    layoutClose(bounds: bounds)
    layoutToolbar(bounds: bounds)
  }

}
