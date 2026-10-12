import CoreGraphics

enum AnnotationPresets {
  static let palette: [CodableColor] = [
    CodableColor(r: 0.937, g: 0.267, b: 0.267),
    CodableColor(r: 0.961, g: 0.620, b: 0.043),
    CodableColor(r: 0.918, g: 0.702, b: 0.031),
    CodableColor(r: 0.133, g: 0.773, b: 0.369),
    CodableColor(r: 0.231, g: 0.510, b: 0.965),
    CodableColor(r: 1, g: 1, b: 1),
    CodableColor(r: 0, g: 0, b: 0),
  ]

  static let strokeWidths: [CGFloat] = [2, 3, 5, 8]
  static let defaultStrokeWidth: CGFloat = 3
  static let defaultFontSize: CGFloat = 18
  static let defaultBlurRadius: CGFloat = 12
  static let defaultPixelateBlock: CGFloat = 12
  static let defaultHighlighterOpacity: CGFloat = 0.35
  static let defaultHighlighterWidth: CGFloat = 16

  static var defaultColor: CodableColor {
    palette[0]
  }

  static var highlighterColor: CodableColor {
    palette[2]
  }

  static func style(for kind: AnnotationToolKind) -> AnnotationStyle {
    switch kind {
    case .arrow:
      return strokeStyle()
    case .rectangle:
      return shapeStyle()
    case .ellipse:
      return shapeStyle()
    case .line:
      return strokeStyle()
    case .pen:
      return strokeStyle()
    case .highlighter:
      return AnnotationStyle(
        strokeColor: highlighterColor,
        strokeWidth: defaultHighlighterWidth,
        opacity: defaultHighlighterOpacity
      )
    case .text:
      return AnnotationStyle(strokeColor: defaultColor, fontSize: defaultFontSize)
    case .blur:
      return AnnotationStyle(strokeColor: defaultColor, blurRadius: defaultBlurRadius)
    case .pixelate:
      return AnnotationStyle(strokeColor: defaultColor, blurRadius: defaultPixelateBlock)
    case .crop:
      return AnnotationStyle(strokeColor: defaultColor)
    }
  }

  static func strokeStyle() -> AnnotationStyle {
    AnnotationStyle(strokeColor: defaultColor, strokeWidth: defaultStrokeWidth)
  }

  static func shapeStyle() -> AnnotationStyle {
    AnnotationStyle(strokeColor: defaultColor, fillColor: nil, strokeWidth: defaultStrokeWidth)
  }
}
