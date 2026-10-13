import SwiftUI

struct SettingsScreenshotsTab: View {
  @State private var prefix = ScreenshotNaming.storedPrefix
  @State private var example = ScreenshotNaming.previewName()

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
      VStack(alignment: .leading, spacing: 6) {
        Text("File name prefix")
          .font(.system(size: FontSize.xs, weight: .medium))
          .foregroundStyle(ReframedColors.primaryText)

        HStack(spacing: 8) {
          TextField("", text: $prefix)
            .textFieldStyle(.plain)
            .font(.system(size: FontSize.xs))
            .foregroundStyle(ReframedColors.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ReframedColors.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(ReframedColors.border))
            .onChange(of: prefix) { _, value in
              ScreenshotNaming.storedPrefix = value
              example = ScreenshotNaming.previewName(prefix: value)
            }

          Button("Default") {
            prefix = ScreenshotNaming.defaultPrefix
            ScreenshotNaming.resetPrefix()
            example = ScreenshotNaming.previewName()
          }
          .buttonStyle(OutlineButtonStyle(size: .small))
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("Saved as")
          .font(.system(size: FontSize.xs, weight: .medium))
          .foregroundStyle(ReframedColors.primaryText)
        Text(example)
          .font(.system(size: FontSize.xs, design: .monospaced))
          .foregroundStyle(ReframedColors.secondaryText)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
