import AppKit
import CoreGraphics

@MainActor
final class ScrollingCaptureHUDWindow: NSPanel {
  static let size = CGSize(width: 360, height: 64)

  private let status = NSTextField(labelWithString: "Waiting for the first frame \u{00b7} Esc to cancel")
  private var onFinish: (() -> Void)?
  private var onCancel: (() -> Void)?

  init(displayID: CGDirectDisplayID, anchor: CGRect, onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
    self.onFinish = onFinish
    self.onCancel = onCancel
    let box = NSRect(origin: .zero, size: Self.size)
    super.init(contentRect: box, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    ignoresMouseEvents = true
    isFloatingPanel = true
    isMovableByWindowBackground = false
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = false
    level = .screenSaver
    sharingType = .none
    animationBehavior = .none
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    contentView = makeContent()
    place(displayID: displayID, anchor: anchor)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 76:
      onFinish?()
    case 53:
      onCancel?()
    default:
      super.keyDown(with: event)
    }
  }

  func present() {
    makeKeyAndOrderFront(nil)
    orderFrontRegardless()
  }

  func update(count: Int) {
    status.stringValue = (count == 1 ? "1 frame" : "\(count) frames") + " \u{00b7} Esc to cancel"
  }

  func dismiss() {
    orderOut(nil)
    contentView = nil
    onFinish = nil
    onCancel = nil
  }

  private func makeContent() -> NSView {
    let content = NSView(frame: NSRect(origin: .zero, size: Self.size))
    content.wantsLayer = true
    content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
    content.layer?.cornerRadius = Radius.xl
    let headline = NSTextField(labelWithString: "Scroll the page, then press Return to finish")
    headline.font = .systemFont(ofSize: FontSize.sm, weight: .semibold)
    headline.textColor = .white
    headline.frame = NSRect(x: 16, y: 34, width: 328, height: 18)
    status.font = .systemFont(ofSize: FontSize.xs)
    status.textColor = NSColor.white.withAlphaComponent(0.72)
    status.frame = NSRect(x: 16, y: 14, width: 328, height: 16)
    content.addSubview(headline)
    content.addSubview(status)
    return content
  }

  private func place(displayID: CGDirectDisplayID, anchor: CGRect) {
    guard let screen = NSScreen.screen(for: displayID) ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let margin: CGFloat = 14
    var origin = CGPoint(x: anchor.midX - Self.size.width / 2, y: visible.minY + 24)
    if anchor.minY - Self.size.height - margin >= visible.minY {
      origin.y = anchor.minY - Self.size.height - margin
    } else if anchor.maxY + Self.size.height + margin <= visible.maxY {
      origin.y = anchor.maxY + margin
    }
    origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - Self.size.width - 8)
    setFrameOrigin(origin)
  }
}
