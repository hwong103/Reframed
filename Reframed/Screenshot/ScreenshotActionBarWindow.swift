import AppKit
import SwiftUI

@MainActor
final class ScreenshotActionBarWindow: NSPanel {
  private static let displayDuration: Duration = .seconds(8)
  private static var current: ScreenshotActionBarWindow?

  private let captureRect: CGRect
  private let onCopy: () -> Void
  private let onSaveAndCopy: () -> String
  private let onAnnotate: () -> Void
  private let onCopyText: () -> String
  private let onPin: () -> Void
  private var dismissTask: Task<Void, Never>?

  static var isVisible: Bool { current != nil }

  static func show(
    near rect: CGRect,
    onCopy: @escaping () -> Void,
    onSaveAndCopy: @escaping () -> String,
    onAnnotate: @escaping () -> Void,
    onCopyText: @escaping () -> String,
    onPin: @escaping () -> Void
  ) {
    current?.dismissNow()
    let window = ScreenshotActionBarWindow(
      captureRect: rect,
      onCopy: onCopy,
      onSaveAndCopy: onSaveAndCopy,
      onAnnotate: onAnnotate,
      onCopyText: onCopyText,
      onPin: onPin
    )
    current = window
    window.render(status: "Copied to clipboard")
    window.orderFrontRegardless()
    window.makeKey()
    window.scheduleDismiss(after: Self.displayDuration)
  }

  static func dismiss() {
    current?.dismissNow()
  }

  private init(
    captureRect: CGRect,
    onCopy: @escaping () -> Void,
    onSaveAndCopy: @escaping () -> String,
    onAnnotate: @escaping () -> Void,
    onCopyText: @escaping () -> String,
    onPin: @escaping () -> Void
  ) {
    self.captureRect = captureRect
    self.onCopy = onCopy
    self.onSaveAndCopy = onSaveAndCopy
    self.onAnnotate = onAnnotate
    self.onCopyText = onCopyText
    self.onPin = onPin

    super.init(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isFloatingPanel = true
    isMovableByWindowBackground = false
    hidesOnDeactivate = false
    level = .screenSaver
    sharingType = .none
    animationBehavior = .none
    appearance = NSAppearance(named: .darkAqua)
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 53:
      dismissNow()
    case 36, 76:
      annotateNow()
    default:
      super.keyDown(with: event)
    }
  }

  private func render(status: String) {
    let view = ScreenshotActionBarView(
      status: status,
      onCopy: { [weak self] in
        guard let self else { return }
        self.onCopy()
        self.dismissNow()
      },
      onSaveAndCopy: { [weak self] in
        guard let self else { return }
        self.render(status: self.onSaveAndCopy())
        self.scheduleDismiss(after: .seconds(2.4))
      },
      onAnnotate: { [weak self] in
        guard let self else { return }
        self.annotateNow()
      },
      onCopyText: { [weak self] in
        guard let self else { return }
        self.render(status: self.onCopyText())
        self.scheduleDismiss(after: .seconds(2.4))
      },
      onPin: { [weak self] in
        guard let self else { return }
        self.onPin()
        self.dismissNow()
      }
    )
    let hosting = NSHostingView(rootView: view)
    hosting.sizingOptions = [.intrinsicContentSize]
    contentView = hosting
    let size = hosting.fittingSize
    setFrame(NSRect(origin: resolvedOrigin(for: size), size: size), display: true)
  }

  private func resolvedOrigin(for size: NSSize) -> NSPoint {
    let anchor = CGPoint(x: captureRect.midX, y: captureRect.midY)
    let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? captureRect
    let inset: CGFloat = 16
    var origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + inset)
    if NSRect(origin: origin, size: size).intersects(captureRect) {
      origin = CGPoint(x: captureRect.midX - size.width / 2, y: captureRect.maxY + inset)
    }
    origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
    origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
    return origin
  }

  private func annotateNow() {
    dismissNow()
    onAnnotate()
  }

  private func scheduleDismiss(after duration: Duration) {
    dismissTask?.cancel()
    dismissTask = Task { [weak self] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      self?.dismissNow()
    }
  }

  private func dismissNow() {
    dismissTask?.cancel()
    dismissTask = nil
    orderOut(nil)
    contentView = nil
    if Self.current === self {
      Self.current = nil
    }
  }
}
