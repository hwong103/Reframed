import SwiftUI

@MainActor
struct CaptureDimensionBadge: View {
  let state: CaptureAnnotationState

  var body: some View {
    HStack(spacing: 6) {
      Text("\(Int(state.pointSize.width.rounded())) x \(Int(state.pointSize.height.rounded())) pt")
      lockButton
    }
    .font(.system(size: FontSize.xs, weight: .semibold, design: .monospaced))
    .foregroundStyle(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(CaptureAnnotationChrome.accent, in: Capsule())
    .fixedSize()
    .environment(\.colorScheme, .light)
    .captureArrowCursor()
  }

  private var lockButton: some View {
    Button {
      state.aspectLocked.toggle()
    } label: {
      Image(systemName: state.aspectLocked ? "lock.fill" : "lock.open")
        .font(.system(size: FontSize.xs, weight: .bold))
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }
    .buttonStyle(PlainCustomButtonStyle())
    .help(state.aspectLocked ? "Unlock aspect ratio" : "Lock aspect ratio")
    .captureArrowCursor()
  }
}

@MainActor
struct CaptureCloseButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Color.black.opacity(0.72))
        .frame(width: 28, height: 28)
        .background(Circle().fill(Color.white))
        .shadow(color: CaptureAnnotationChrome.shadow, radius: 4, y: 1)
        .contentShape(Circle())
    }
    .buttonStyle(PlainCustomButtonStyle())
    .help("Cancel (Esc)")
    .captureArrowCursor()
  }
}
