import SwiftUI

struct AnnotationToolbarCommands {
  let copy: () -> Void
  let saveAndCopy: () -> Void
  let close: () -> Void
}

@MainActor
struct AnnotationToolbarView: View {
  let model: AnnotationEditorModel
  let commands: AnnotationToolbarCommands

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        toolPicker
        divider
        palette
        divider
        historyControls
        Spacer(minLength: 0)
      }
      HStack(spacing: 10) {
        SliderRow(
          label: "Stroke",
          labelWidth: 42,
          value: strokeBinding,
          range: 1...24,
          step: 1,
          formattedValue: "\(Int(model.strokeWidth))",
          valueWidth: 24
        )
        .frame(width: 148)
        SliderRow(
          label: "Blur",
          labelWidth: 30,
          value: blurBinding,
          range: 2...48,
          step: 1,
          formattedValue: "\(Int(model.blurRadius))",
          valueWidth: 24
        )
        .frame(width: 136)
        SliderRow(
          label: "Text",
          labelWidth: 30,
          value: fontSizeBinding,
          range: 10...72,
          step: 1,
          formattedValue: "\(Int(model.fontSize))",
          valueWidth: 24
        )
        .frame(width: 136)
        Spacer(minLength: 0)
        cropControls
        actionControls
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(ReframedColors.backgroundContainer)
  }

  private var divider: some View {
    Rectangle()
      .fill(ReframedColors.border)
      .frame(width: 1, height: 20)
  }

  private var toolPicker: some View {
    HStack(spacing: 2) {
      ForEach(AnnotationToolKind.allCases, id: \.self) { kind in
        ToolIconButton(
          icon: AnnotationToolbarView.label(for: kind).icon,
          title: AnnotationToolbarView.label(for: kind).title,
          isSelected: model.tool == kind
        ) {
          model.setTool(kind)
        }
      }
    }
  }

  private var palette: some View {
    HStack(spacing: 4) {
      ForEach(AnnotationPresets.palette, id: \.hexString) { color in
        SwatchButton(fill: Color(cgColor: color.cgColor), isSelected: model.strokeColor == color) {
          model.setStrokeColor(color)
        }
        .frame(width: 20, height: 20)
      }
    }
  }

  private var historyControls: some View {
    HStack(spacing: 2) {
      IconButton(systemName: "arrow.uturn.backward") { model.undo() }
        .disabled(!model.canUndo)
      IconButton(systemName: "arrow.uturn.forward") { model.redo() }
        .disabled(!model.canRedo)
    }
  }

  @ViewBuilder private var cropControls: some View {
    if model.pendingCrop != nil {
      Button("Apply") { model.applyPendingCrop() }
        .buttonStyle(PrimaryButtonStyle())
      Button("Cancel") { model.setPendingCrop(nil) }
        .buttonStyle(OutlineButtonStyle())
    }
  }

  private var actionControls: some View {
    HStack(spacing: 8) {
      Button("Copy", action: commands.copy)
        .buttonStyle(SecondaryButtonStyle())
      Button("Save & Copy", action: commands.saveAndCopy)
        .buttonStyle(PrimaryButtonStyle())
      Button("Close", action: commands.close)
        .buttonStyle(OutlineButtonStyle())
    }
  }

  private var strokeBinding: Binding<CGFloat> {
    Binding(get: { model.strokeWidth }, set: { model.setStrokeWidth($0) })
  }

  private var blurBinding: Binding<CGFloat> {
    Binding(get: { model.blurRadius }, set: { model.setBlurRadius($0) })
  }

  private var fontSizeBinding: Binding<CGFloat> {
    Binding(get: { model.fontSize }, set: { model.setFontSize($0) })
  }

  private static func label(for kind: AnnotationToolKind) -> (icon: String, title: String) {
    switch kind {
    case .arrow: ("arrow.up.right", "Arrow")
    case .rectangle: ("rectangle", "Rectangle")
    case .ellipse: ("circle", "Ellipse")
    case .line: ("line.diagonal", "Line")
    case .pen: ("pencil", "Pen")
    case .highlighter: ("highlighter", "Highlighter")
    case .text: ("textformat", "Text")
    case .blur: ("camera.filters", "Blur")
    case .pixelate: ("square.grid.2x2", "Pixelate")
    case .crop: ("crop", "Crop")
    }
  }
}

private struct ToolIconButton: View {
  let icon: String
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: FontSize.xs))
        .foregroundStyle(ReframedColors.primaryText)
        .frame(width: 28, height: 28)
        .background(isSelected ? ReframedColors.selectedBackground : Color.clear, in: RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(RoundedRectangle(cornerRadius: Radius.md))
    }
    .buttonStyle(PlainCustomButtonStyle())
    .hoverEffect(hoverColor: ReframedColors.hoverBackground)
    .help(title)
  }
}
