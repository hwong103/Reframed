import AppKit
import SwiftUI

struct CaptureAnnotationDragSource: NSViewRepresentable {
  let makeItem: () -> NSPasteboardItem?

  func makeNSView(context: Context) -> DragView {
    let view = DragView()
    view.makeItem = makeItem
    return view
  }

  func updateNSView(_ view: DragView, context: Context) {
    view.makeItem = makeItem
  }

  final class DragView: NSView, NSDraggingSource {
    var makeItem: (() -> NSPasteboardItem?)?

    private var startPoint: NSPoint?
    private var isDragging = false
    private var isHovering = false

    override var intrinsicContentSize: NSSize {
      NSSize(width: 32, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
      if isHovering {
        NSColor.black.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
      }
      guard
        let symbol = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
      else { return }
      symbol.isTemplate = true
      NSColor(white: 0.22, alpha: 1).set()
      let side: CGFloat = 15
      let rect = NSRect(
        x: bounds.midX - side / 2,
        y: bounds.midY - side / 2,
        width: side,
        height: side
      )
      symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      for area in trackingAreas {
        removeTrackingArea(area)
      }
      addTrackingArea(
        NSTrackingArea(
          rect: bounds,
          options: [.mouseEnteredAndExited, .activeAlways],
          owner: self
        )
      )
    }

    override func mouseEntered(with event: NSEvent) {
      isHovering = true
      NSCursor.arrow.set()
      needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
      isHovering = false
      needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
      startPoint = convert(event.locationInWindow, from: nil)
      isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
      guard !isDragging, let start = startPoint else { return }
      let point = convert(event.locationInWindow, from: nil)
      guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
      guard let item = makeItem?() else { return }
      isDragging = true
      let draggingItem = NSDraggingItem(pasteboardWriter: item)
      draggingItem.setDraggingFrame(bounds, contents: previewImage())
      beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
      startPoint = nil
      isDragging = false
    }

    func draggingSession(
      _ session: NSDraggingSession,
      sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
      .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
      true
    }

    private func previewImage() -> NSImage {
      NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        ?? NSImage(size: bounds.size)
    }
  }
}
