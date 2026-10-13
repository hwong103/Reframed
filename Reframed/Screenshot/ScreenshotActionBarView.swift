import SwiftUI

struct ScreenshotActionBarView: View {
  let status: String
  let onCopy: () -> Void
  let onSaveAndCopy: () -> Void
  let onAnnotate: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      HStack(spacing: 5) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: FontSize.xs, weight: .semibold))
        Text(status)
          .font(.system(size: FontSize.xs, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 4)
      .frame(maxWidth: 260, alignment: .leading)

      Rectangle()
        .fill(Color.white.opacity(0.2))
        .frame(width: 1, height: 18)

      annotateButton
      actionButton(icon: "doc.on.doc", title: "Copy", help: "Copy to clipboard", action: onCopy)
      actionButton(
        icon: "square.and.arrow.down",
        title: "Save & Copy",
        help: "Save a PNG and copy it",
        action: onSaveAndCopy
      )
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: Radius.lg))
    .fixedSize()
  }

  private func actionButton(
    icon: String,
    title: String,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      itemLabel(icon: icon, title: title)
        .foregroundStyle(.white)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md))
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private var annotateButton: some View {
    Button(action: onAnnotate) {
      itemLabel(icon: "pencil.tip.crop.circle", title: "Annotate")
    }
    .buttonStyle(PrimaryButtonStyle(size: .small))
    .help("Annotate the capture")
  }

  private func itemLabel(icon: String, title: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.system(size: FontSize.xs))
      Text(title)
        .font(.system(size: FontSize.xs, weight: .medium))
    }
    .padding(.horizontal, 8)
    .frame(height: 26)
  }
}
