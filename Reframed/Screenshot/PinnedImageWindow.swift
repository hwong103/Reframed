import AppKit
import CoreGraphics
import Foundation

@MainActor
final class PinnedImageWindow: NSPanel, NSWindowDelegate {
  let pinID: String
  let displayID: CGDirectDisplayID
  let pngData: Data
  var onClose: ((String) -> Void)?
  var onFrameChange: ((String) -> Void)?

  private static let minimumSide: CGFloat = 60
  private let maxSide: CGFloat = 4096
  private let aspect: CGFloat

  init(image: CGImage, pngData: Data, displayID: CGDirectDisplayID, pinID: String) {
    self.pinID = pinID
    self.displayID = displayID
    self.pngData = pngData
    self.aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
    let size = Self.naturalSize(for: image, displayID: displayID)

    super.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isFloatingPanel = true
    hidesOnDeactivate = false
    isMovableByWindowBackground = true
    level = .floating
    sharingType = .none
    animationBehavior = .none
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    contentView = PinnedImageContentView(
      image: image,
      onResize: { [weak self] delta in self?.resize(by: delta) },
      onClose: { [weak self] in self?.requestClose() }
    )
    delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      requestClose()
    } else {
      super.keyDown(with: event)
    }
  }

  func windowDidMove(_ notification: Notification) {
    onFrameChange?(pinID)
  }

  func windowDidResize(_ notification: Notification) {
    onFrameChange?(pinID)
  }

  func present(near point: CGPoint?) {
    let size = frame.size
    let anchor = point ?? NSEvent.mouseLocation
    let visible = (NSScreen.screen(for: displayID) ?? NSScreen.main)?.visibleFrame
    let origin = confined(CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2), size, on: visible)
    setFrameOrigin(origin)
    orderFrontRegardless()
    onFrameChange?(pinID)
  }

  private func confined(_ origin: CGPoint, _ size: CGSize, on visible: CGRect?) -> CGPoint {
    guard let visible else { return origin }
    let x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
    let y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
    return CGPoint(x: x, y: y)
  }

  func requestClose() {
    orderOut(nil)
    contentView = nil
    onClose?(pinID)
  }

  private func resize(by delta: CGFloat) {
    var width = min(max(frame.width + delta, Self.minimumSide), maxSide)
    var height = width / aspect
    let visible = (screen ?? NSScreen.screen(for: displayID) ?? NSScreen.main)?.visibleFrame
    if let visible {
      let ratio = min(1, min(visible.width * 0.9 / max(width, 1), visible.height * 0.9 / max(height, 1)))
      width *= ratio
      height *= ratio
    }
    var newFrame = frame
    newFrame.origin.y += frame.height - height
    newFrame.size = CGSize(width: width, height: height)
    newFrame.origin = confined(newFrame.origin, newFrame.size, on: visible)
    setFrame(newFrame, display: true)
    onFrameChange?(pinID)
  }
  private static func naturalSize(for image: CGImage, displayID: CGDirectDisplayID) -> CGSize {
    let scale = NSScreen.screen(for: displayID)?.backingScaleFactor ?? 2
    let width = CGFloat(image.width) / scale
    let height = CGFloat(image.height) / scale
    guard width > 0, height > 0 else { return CGSize(width: minimumSide, height: minimumSide) }
    let floorRatio = max(1, minimumSide / width, minimumSide / height)
    let size = CGSize(width: width * floorRatio, height: height * floorRatio)
    guard let limit = NSScreen.screen(for: displayID)?.visibleFrame else { return size }
    let ratio = min(1, min(limit.width * 0.8 / max(size.width, 1), limit.height * 0.8 / max(size.height, 1)))
    return CGSize(width: size.width * ratio, height: size.height * ratio)
  }
}

@MainActor
private final class PinnedImageContentView: NSView {
  private let image: CGImage
  private let onResize: (CGFloat) -> Void
  private let onClose: () -> Void
  private let closeButton = NSButton()
  private var trackingArea: NSTrackingArea?

  init(image: CGImage, onResize: @escaping (CGFloat) -> Void, onClose: @escaping () -> Void) {
    self.image = image
    self.onResize = onResize
    self.onClose = onClose
    super.init(frame: .zero)

    closeButton.isBordered = false
    closeButton.bezelStyle = .shadowlessSquare
    closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
    closeButton.contentTintColor = .white
    closeButton.imagePosition = .imageOnly
    closeButton.target = self
    closeButton.action = #selector(closeTapped)
    closeButton.isHidden = true
    addSubview(closeButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var acceptsFirstResponder: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.interpolationQuality = .high
    context.draw(image, in: bounds)
  }

  override func layout() {
    super.layout()
    closeButton.frame = NSRect(x: 6, y: bounds.maxY - 24, width: 18, height: 18)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    closeButton.isHidden = false
  }

  override func mouseExited(with event: NSEvent) {
    closeButton.isHidden = true
  }

  override func scrollWheel(with event: NSEvent) {
    onResize(event.scrollingDeltaY)
  }

  @objc private func closeTapped() {
    onClose()
  }
}
