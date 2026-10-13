import AppKit
import SwiftUI

@MainActor
enum CaptureAnnotationChrome {
  static let surface = ReframedColors.overlayCardBackground
  static let icon = Color(white: 0.22)
  static let divider = Color.black.opacity(0.12)
  static let accent = Color.accentColor
  static let delete = Color(red: 0.86, green: 0.18, blue: 0.18)
  static let shadow = Color.black.opacity(0.22)
  static var activeBackground: Color { Color.accentColor.opacity(0.16) }
}

extension View {
  func captureArrowCursor() -> some View {
    pointerStyle(.default)
      .onHover { hovering in
        if hovering {
          NSCursor.arrow.set()
        }
      }
  }
}

extension CaptureAnnotationToolbarView {
  struct IconButton: View {
    let systemImage: String
    var isSelected: Bool = false
    var tint: Color = CaptureAnnotationChrome.icon
    var isDimmed: Bool = false
    let help: String
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Image(systemName: systemImage)
          .font(.system(size: FontSize.sm + 1, weight: .medium))
          .foregroundStyle(isSelected ? CaptureAnnotationChrome.accent : tint)
          .frame(width: 32, height: 32)
          .background(
            isSelected ? CaptureAnnotationChrome.activeBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: Radius.lg)
          )
          .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
          .opacity(isDimmed ? 0.35 : 1)
      }
      .buttonStyle(PlainCustomButtonStyle())
      .help(help)
      .captureArrowCursor()
    }
  }
}

@MainActor
struct AnnotationColorPopover: View {
  @Bindable var state: CaptureAnnotationState
  let onStyleChange: () -> Void
  let onSetDefault: () -> Void

  private static let swatches: [CodableColor] = [
    CodableColor(r: 0.937, g: 0.267, b: 0.267),
    CodableColor(r: 0.231, g: 0.510, b: 0.965),
    CodableColor(r: 0.133, g: 0.773, b: 0.369),
    CodableColor(r: 0.961, g: 0.620, b: 0.043),
    CodableColor(r: 0.0, g: 0.0, b: 0.0),
    CodableColor(r: 0.25, g: 0.25, b: 0.25),
    CodableColor(r: 0.55, g: 0.55, b: 0.55),
    CodableColor(r: 1.0, g: 1.0, b: 1.0),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 13) {
        currentColor
        divider
        swatchGrid
      }
      styleSliders
      Button("Set as Default Style", action: onSetDefault)
        .buttonStyle(SecondaryButtonStyle(size: .small, forceLightMode: true))
    }
    .padding(15)
    .frame(width: 312)
    .background(CaptureAnnotationChrome.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(CaptureAnnotationChrome.divider))
    .environment(\.colorScheme, .light)
    .captureArrowCursor()
  }

  private var currentColor: some View {
    Circle()
      .fill(Color(cgColor: state.selectedColor.cgColor))
      .frame(width: 33, height: 33)
      .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 2))
  }

  private var divider: some View {
    Rectangle()
      .fill(CaptureAnnotationChrome.divider)
      .frame(width: 1, height: 33)
  }

  private var swatchGrid: some View {
    VStack(spacing: 8) {
      swatchRow(Self.swatches[0...3])
      swatchRow(Self.swatches[4...7])
    }
  }

  private func swatchRow(_ colors: ArraySlice<CodableColor>) -> some View {
    HStack(spacing: 8) {
      ForEach(Array(colors.enumerated()), id: \.element.hexString) { _, color in
        SwatchButton(fill: Color(cgColor: color.cgColor), isSelected: color == state.selectedColor) {
          state.selectedColor = color
          onStyleChange()
        }
        .frame(width: 26, height: 26)
      }
    }
  }

  private var styleSliders: some View {
    VStack(alignment: .leading, spacing: 8) {
      SliderRow(
        label: "Opacity",
        labelWidth: 72,
        value: $state.opacity,
        range: 0.1...1,
        step: 0.05,
        formattedValue: "\(Int((state.opacity * 100).rounded()))%"
      )
      SliderRow(
        label: "Thickness",
        labelWidth: 72,
        value: $state.thickness,
        range: 1...24,
        step: 1,
        formattedValue: "\(Int(state.thickness))"
      )
      SliderRow(
        label: "Size",
        labelWidth: 72,
        value: $state.size,
        range: 4...96,
        step: 1,
        formattedValue: "\(Int(state.size))"
      )
    }
  }
}
