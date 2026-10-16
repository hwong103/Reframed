import AppKit
import ScreenCaptureKit
import SwiftUI

struct ScreenshotWindowSelectionView: View {
  let screen: NSScreen
  let request: WindowSelectionRequest
  @ObservedObject var windowController: WindowController

  private func toLocal(_ rect: CGRect) -> CGRect {
    let screenBounds = CGDisplayBounds(screen.displayID)
    return CGRect(
      x: rect.origin.x - screenBounds.origin.x,
      y: rect.origin.y - screenBounds.origin.y,
      width: rect.width,
      height: rect.height
    )
  }

  private var hoveredWindow: WindowInfo? {
    guard let current = windowController.currentWindow else { return nil }
    let screenBounds = CGDisplayBounds(screen.displayID)
    let mid = CGPoint(x: current.frame.midX, y: current.frame.midY)
    guard mid.x >= screenBounds.origin.x,
      mid.x < screenBounds.origin.x + screenBounds.width,
      mid.y >= screenBounds.origin.y,
      mid.y < screenBounds.origin.y + screenBounds.height
    else { return nil }
    return current
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Canvas { context, size in
          let fullRect = CGRect(origin: .zero, size: size)
          context.fill(Path(fullRect), with: .color(ReframedColors.overlayDimBackground))

          guard let window = hoveredWindow else { return }

          let targetRect = toLocal(window.frame)
          let targetPath = Path(roundedRect: targetRect, cornerRadius: 10)

          context.blendMode = .destinationOut
          context.fill(targetPath, with: .color(.black))
          context.blendMode = .normal

          context.fill(targetPath, with: .color(.white.opacity(0.55)))
          context.stroke(targetPath, with: .color(.white), lineWidth: 2)
        }
        .edgesIgnoringSafeArea(.all)

        if let current = hoveredWindow {
          card(for: current)
            .position(x: toLocal(current.frame).midX, y: toLocal(current.frame).midY)
        } else {
          hintCard
        }

        hiddenControls
      }
    }
  }

  private func card(for window: WindowInfo) -> some View {
    VStack(spacing: 12) {
      if let app = NSRunningApplication(processIdentifier: window.appPID),
        let icon = app.icon
      {
        Image(nsImage: icon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 64, height: 64)
      }

      Text(window.appName)
        .font(.system(size: FontSize.xs, weight: .medium))
        .foregroundStyle(Color.black)

      if !window.title.isEmpty && window.title != window.appName {
        Text(window.title)
          .font(.system(size: FontSize.xs))
          .foregroundStyle(Color.black.opacity(0.6))
          .lineLimit(1)
      }

      Text("\(Int(window.frame.width)) \u{00d7} \(Int(window.frame.height))")
        .font(.system(size: FontSize.xs))
        .foregroundStyle(Color.black.opacity(0.6))

      Button {
        request.onConfirm(window)
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "camera")
          Text(request.confirmTitle)
        }
      }
      .buttonStyle(PrimaryButtonStyle(size: .large, forceLightMode: true))

      Text(request.hint)
        .font(.system(size: FontSize.xxs))
        .foregroundStyle(Color.black.opacity(0.35))
    }
    .padding(24)
    .background(ReframedColors.overlayCardBackground)
    .clipShape(RoundedRectangle(cornerRadius: Radius.xxl))
    .shadow(radius: 20)
  }

  private var hintCard: some View {
    VStack(spacing: 8) {
      Text("Hover over a window to select it")
        .font(.system(size: FontSize.sm, weight: .medium))
        .foregroundStyle(Color.black)
      Text("Tab to cycle \u{00b7} Esc to cancel")
        .font(.system(size: FontSize.xxs))
        .foregroundStyle(Color.black.opacity(0.35))
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
    .background(ReframedColors.overlayCardBackground)
    .clipShape(RoundedRectangle(cornerRadius: Radius.xxl))
    .shadow(radius: 20)
  }

  private var hiddenControls: some View {
    Group {
      Button("") {
        request.onCancel()
      }
      .keyboardShortcut(.escape, modifiers: [])
      .opacity(0)
      .frame(width: 0, height: 0)

      Button("") {
        windowController.cycleToNextWindow()
      }
      .keyboardShortcut(.tab, modifiers: [])
      .opacity(0)
      .frame(width: 0, height: 0)

      Button("") {
        windowController.cycleToPreviousWindow()
      }
      .keyboardShortcut(.tab, modifiers: .shift)
      .opacity(0)
      .frame(width: 0, height: 0)

      Button("") {
        if let window = hoveredWindow {
          request.onConfirm(window)
        }
      }
      .keyboardShortcut(.return, modifiers: [])
      .opacity(0)
      .frame(width: 0, height: 0)
    }
  }
}
