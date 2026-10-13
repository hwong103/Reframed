import AppKit
import SwiftUI

@MainActor
final class ScreenshotFeedbackWindow: NSPanel {
  private static let displayDuration: Duration = .seconds(1.2)
  private static var current: ScreenshotFeedbackWindow?

  private var dismissTask: Task<Void, Never>?
  private let sticky: Bool

  static func show(_ message: String, detail: String? = nil, near point: CGPoint, sticky: Bool = false) {
    current?.dismissNow()
    let window = ScreenshotFeedbackWindow(message: message, detail: detail, sticky: sticky)
    current = window
    window.place(near: point)
    window.orderFrontRegardless()
    window.scheduleDismiss()
  }

  static func dismissCurrent() {
    current?.dismissNow()
  }

  private init(message: String, detail: String?, sticky: Bool) {
    self.sticky = sticky
    let hosting = NSHostingView(rootView: ScreenshotFeedbackView(message: message, detail: detail, sticky: sticky))
    hosting.sizingOptions = [.intrinsicContentSize]
    let size = hosting.fittingSize

    super.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    ignoresMouseEvents = true
    isFloatingPanel = true
    isMovableByWindowBackground = false
    hidesOnDeactivate = false
    level = .screenSaver
    sharingType = .none
    animationBehavior = .none
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    contentView = hosting
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  private func place(near point: CGPoint) {
    let anchor = NSScreen.screens.contains { $0.frame.contains(point) } ? point : NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main else {
      return
    }
    let visible = screen.visibleFrame
    var origin = CGPoint(x: anchor.x - frame.width / 2, y: anchor.y + 22)
    if origin.y + frame.height > visible.maxY {
      origin.y = anchor.y - frame.height - 22
    }
    origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
    origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
    setFrameOrigin(origin)
  }

  private func scheduleDismiss() {
    guard !sticky else { return }
    dismissTask = Task { [weak self] in
      try? await Task.sleep(for: Self.displayDuration)
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

private struct ScreenshotFeedbackView: View {
  let message: String
  let detail: String?
  let sticky: Bool

  var body: some View {
    HStack(spacing: 8) {
      if sticky {
        ProgressView()
          .controlSize(.small)
          .progressViewStyle(.circular)
          .tint(.white)
          .frame(width: FontSize.sm, height: FontSize.sm)
      } else {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: FontSize.sm, weight: .semibold))
          .foregroundStyle(.white)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(message)
          .font(.system(size: FontSize.xs, weight: .semibold))
          .foregroundStyle(.white)

        if let detail {
          Text(detail)
            .font(.system(size: FontSize.xxs))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(Color.black.opacity(0.78), in: Capsule())
    .fixedSize()
  }
}
