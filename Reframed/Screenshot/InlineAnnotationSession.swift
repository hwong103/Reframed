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
  let isResizable: Bool
  lazy var model = AnnotationEditorModel(image: image, reference: reference)
  lazy var canvas: AnnotationCanvasView = {
    let view = AnnotationCanvasView(model: model)
    view.isInline = true
    return view
  }()
  lazy var clip: NSView = {
    let container = NSView(frame: CGRect(origin: .zero, size: displaySize))
    container.wantsLayer = true
    container.layer?.masksToBounds = true
    container.addSubview(canvas)
    return container
  }()
  lazy var chrome = SelectionChromeView()
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
  var isReadingText = false

  private var displayScale: CGFloat {
    selection.backingScaleFactor > 0 ? selection.backingScaleFactor : 2
  }

  init(
    image: CGImage,
    selection: SelectionRect,
    localRect: CGRect,
    displaySize: CGSize,
    handlers: SelectionAnnotationHandlers,
    isResizable: Bool = true
  ) {
    self.image = image
    self.selection = selection
    self.localRect = localRect
    self.displaySize = displaySize
    self.handlers = handlers
    self.isResizable = isResizable
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
    applyBeautify()
    refreshState()
  }

  func update(bounds: CGRect, localRect: CGRect, selection: SelectionRect) {
    self.localRect = localRect
    self.selection = selection
    applyBeautify()
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
    model.setBlurRadius(max(4, state.redaction))
  }

  func refreshState() {
    state.canUndo = model.canUndo
    state.canRedo = model.canRedo
    state.hasSelection = model.selectionID != nil
  }

  func cancel() {
    handlers.cancel()
  }

  private func layout(bounds: CGRect) {
    let scale = displayScale
    let origin = CGPoint(
      x: (localRect.minX * scale).rounded() / scale,
      y: (localRect.minY * scale).rounded() / scale
    )
    localRect = CGRect(origin: origin, size: localRect.size)
    state.pointSize = localRect.size
    clip.frame = localRect
    clip.layer?.contentsScale = scale
    let canvasOrigin = isResizable ? CGPoint(x: -origin.x, y: -origin.y) : .zero
    canvas.frame = CGRect(origin: canvasOrigin, size: displaySize)
    canvas.syncContentsScale()
    chrome.frame = bounds
    chrome.isHidden = !isResizable
    chrome.selectionRect = localRect
    chrome.needsDisplay = true
    let badgeSize = badgeHost.fittingSize
    layoutBadge(badgeSize: badgeSize, bounds: bounds)
    layoutClose(bounds: bounds)
    layoutToolbar(bounds: bounds)
  }

}
