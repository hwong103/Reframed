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
  private var dismissTask: Task<Void, Never>?

  static var isVisible: Bool { current != nil }

  static func show(
    near rect: CGRect,
    onCopy: @escaping () -> Void,
    onSaveAndCopy: @escaping () -> String,
    onAnnotate: @escaping () -> Void
  ) {
    current?.dismissNow()
    let window = ScreenshotActionBarWindow(
      captureRect: rect,
      onCopy: onCopy,
      onSaveAndCopy: onSaveAndCopy,
      onAnnotate: onAnnotate
    )
    current = window
    window.render(status: "Copied to clipboard")
    window.orderFrontRegardless()
    window.scheduleDismiss(after: Self.displayDuration)
  }

  static func dismiss() {
    current?.dismissNow()
  }

  private init(
    captureRect: CGRect,
    onCopy: @escaping () -> Void,
    onSaveAndCopy: @escaping () -> String,
    onAnnotate: @escaping () -> Void
  ) {
    self.captureRect = captureRect
    self.onCopy = onCopy
    self.onSaveAndCopy = onSaveAndCopy
    self.onAnnotate = onAnnotate

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
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    guard event.keyCode == 53 else {
      super.keyDown(with: event)
      return
    }
    dismissNow()
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
        self.dismissNow()
        self.onAnnotate()
      }
    )
    let hosting = NSHostingView(rootView: view)
    hosting.sizingOptions = [.intrinsicContentSize]
    contentView = hosting
    let size = hosting.fittingSize
    setFrame(NSRect(origin: resolvedOrigin(for: size), size: size), display: true)
  }

  private func resolvedOrigin(for size: NSSize) -> NSPoint {
    let anchor = CGPoint(x: captureRect.midX, y: captureRect.minY)
    let visible = NSScreen.screens.first(where: { $0.frame.contains(anchor) })?.visibleFrame ?? .zero
    var origin = CGPoint(x: captureRect.midX - size.width / 2, y: captureRect.minY - size.height - 12)
    if origin.y < visible.minY + 8 {
      origin.y = captureRect.maxY + 12
    }
    origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
    origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
    return origin
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
