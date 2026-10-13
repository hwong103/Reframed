import AppKit
import SwiftUI

@MainActor
final class SelectionOverlayView: NSView {
  let request: SelectionRequest
  let backgroundImage: CGImage?
  let isInitialActive: Bool
  let hoverProvider: HoverTargetProvider?

  var selectionRect: CGRect?
  var dragOrigin: CGPoint?
  var isDragging = false
  var didDrag = false
  var activeHandle: ResizeHandle?
  var handleDragStart: CGPoint?
  var originalRectBeforeResize: CGRect?
  var mouseLocation: CGPoint = .zero
  var controlsHost: NSHostingView<CaptureAreaView>?
  var annotationSession: InlineAnnotationSession?
  var isFullDisplayInitial = false
  var hoverSuppressed = false
  var committedWindowID: CGWindowID?
  var hoverTarget: HoverTarget?
  var selectedWindowIDs: [CGWindowID] = []
  var selectedWindowRects: [CGWindowID: CGRect] = [:]
  var optionsHeld = false
  var handledShiftClick = false

  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { false }

  init(
    frame: NSRect,
    request: SelectionRequest,
    backgroundImage: CGImage? = nil,
    isInitialActive: Bool = false,
    hoverProvider: HoverTargetProvider? = nil
  ) {
    self.request = request
    self.backgroundImage = backgroundImage
    self.isInitialActive = isInitialActive
    self.hoverProvider = hoverProvider
    super.init(frame: frame)
  }

  required init?(coder: NSCoder) {
    fatalError()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.mouseMoved, .activeAlways, .inVisibleRect],
        owner: self,
        userInfo: nil
      )
    )
    if isInitialActive, request.initialFullScreen, selectionRect == nil {
      selectionRect = bounds
      isFullDisplayInitial = true
      updateControlsPanel()
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    drawOverlay(context: context)
  }

  override func mouseMoved(with event: NSEvent) {
    optionsHeld = event.modifierFlags.contains(.option)
    handleMouseMoved(convert(event.locationInWindow, from: nil))
  }

  override func mouseDown(with event: NSEvent) {
    optionsHeld = event.modifierFlags.contains(.option)
    handleMouseDown(
      convert(event.locationInWindow, from: nil),
      shiftHeld: event.modifierFlags.contains(.shift)
    )
  }

  override func mouseDragged(with event: NSEvent) {
    handleMouseDragged(
      convert(event.locationInWindow, from: nil),
      shiftHeld: event.modifierFlags.contains(.shift)
    )
  }

  override func mouseUp(with event: NSEvent) {
    optionsHeld = event.modifierFlags.contains(.option)
    handleMouseUp(convert(event.locationInWindow, from: nil))
  }

  override func flagsChanged(with event: NSEvent) {
    optionsHeld = event.modifierFlags.contains(.option)
    if annotationSession == nil, selectionRect != nil {
      updateControlsPanel()
    }
    super.flagsChanged(with: event)
  }

  override func keyDown(with event: NSEvent) {
    if let responder = window?.firstResponder, responder is NSTextView {
      return
    }

    switch event.keyCode {
    case 53:  // escape
      request.onCancel()
    case 36:  // enter
      NotificationCenter.default.post(name: .areaSelectionConfirmRequested, object: nil)
    default:
      super.keyDown(with: event)
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let session = annotationSession else {
      return super.hitTest(point)
    }
    if let chrome = annotationHitTest(point) {
      return chrome
    }
    if session.isSelectionToolActive {
      return self
    }
    guard let rect = selectionRect else {
      return super.hitTest(point)
    }
    let local = convert(point, from: superview)
    for handle in ResizeHandle.allCases where handle.rect(for: rect).insetBy(dx: -4, dy: -4).contains(local) {
      return self
    }
    if !rect.contains(local) {
      return self
    }
    return super.hitTest(point)
  }
}
