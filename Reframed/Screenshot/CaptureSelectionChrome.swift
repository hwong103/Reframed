import AppKit

@MainActor
final class SelectionChromeView: NSView {
  var selectionRect: CGRect = .zero

  override var isOpaque: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    guard selectionRect.width >= 1, selectionRect.height >= 1 else { return }
    let accent = NSColor.controlAccentColor

    context.setStrokeColor(accent.cgColor)
    context.setLineWidth(1.5)
    context.stroke(selectionRect.insetBy(dx: -0.75, dy: -0.75))

    for handle in ResizeHandle.allCases {
      let handleRect = handle.rect(for: selectionRect).insetBy(dx: 1, dy: 1)
      context.setFillColor(NSColor.white.cgColor)
      context.fillEllipse(in: handleRect)
      context.setStrokeColor(accent.cgColor)
      context.setLineWidth(1.5)
      context.strokeEllipse(in: handleRect)
    }
  }
}
