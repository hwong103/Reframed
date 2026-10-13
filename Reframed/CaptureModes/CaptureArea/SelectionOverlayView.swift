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
  var isFullDisplayInitial = false
  var hoverSuppressed = false
  var committedWindowID: CGWindowID?
  var hoverTarget: HoverTarget?

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
    handleMouseMoved(convert(event.locationInWindow, from: nil))
  }

  override func mouseDown(with event: NSEvent) {
    handleMouseDown(convert(event.locationInWindow, from: nil))
  }

  override func mouseDragged(with event: NSEvent) {
    handleMouseDragged(
      convert(event.locationInWindow, from: nil),
      shiftHeld: event.modifierFlags.contains(.shift)
    )
  }

  override func mouseUp(with event: NSEvent) {
    handleMouseUp(convert(event.locationInWindow, from: nil))
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
}
