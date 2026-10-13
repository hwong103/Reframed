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

  static let minimumSide: CGFloat = 60
  let maxSide: CGFloat = 4096
  let aspect: CGFloat

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

  func requestClose() {
    orderOut(nil)
    contentView = nil
    onClose?(pinID)
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
