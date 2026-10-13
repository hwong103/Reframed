import CoreGraphics
import Foundation
import Observation

enum CaptureAnnotationTool: String, CaseIterable, Sendable {
  case selection
  case rectangle
  case oval
  case line
  case arrow
  case freehand
  case pixelate
  case blur
  case text
  case step
  case highlight

  var title: String {
    switch self {
    case .selection: return "Selection Tool"
    case .rectangle: return "Rectangle Tool"
    case .oval: return "Oval Tool"
    case .line: return "Line Tool"
    case .arrow: return "Arrow Tool"
    case .freehand: return "Freehand Tool"
    case .pixelate: return "Pixelate Tool"
    case .blur: return "Blur Tool"
    case .text: return "Text Tool"
    case .step: return "Step Annotation Tool"
    case .highlight: return "Highlight Tool"
    }
  }

  var systemImage: String {
    switch self {
    case .selection: return "cursorarrow"
    case .rectangle: return "rectangle"
    case .oval: return "circle"
    case .line: return "line.diagonal"
    case .arrow: return "arrow.up.right"
    case .freehand: return "pencil"
    case .pixelate: return "square.grid.2x2"
    case .blur: return "drop.fill"
    case .text: return "textformat"
    case .step: return "1.circle"
    case .highlight: return "highlighter"
    }
  }

  var keyLabel: String {
    switch self {
    case .selection: return "`"
    case .rectangle: return "1"
    case .oval: return "2"
    case .line: return "3"
    case .arrow: return "4"
    case .freehand: return "5"
    case .pixelate: return "6"
    case .blur: return "0"
    case .text: return "7"
    case .step: return "8"
    case .highlight: return "9"
    }
  }

  var tooltip: String {
    "\(title) (\(keyLabel))"
  }

  var annotationKind: AnnotationToolKind? {
    switch self {
    case .selection: return nil
    case .rectangle: return .rectangle
    case .oval: return .ellipse
    case .line: return .line
    case .arrow: return .arrow
    case .freehand: return .pen
    case .pixelate: return .pixelate
    case .blur: return .blur
    case .text: return .text
    case .step: return .text
    case .highlight: return .highlighter
    }
  }

  static func tool(forKey key: String) -> CaptureAnnotationTool? {
    allCases.first { $0.keyLabel == key }
  }
}

@MainActor
@Observable
final class CaptureAnnotationState {
  var tool: CaptureAnnotationTool = .rectangle
  var selectedColor: CodableColor = CaptureAnnotationDefaults.color
  var opacity: CGFloat = CaptureAnnotationDefaults.opacity
  var thickness: CGFloat = CaptureAnnotationDefaults.thickness
  var size: CGFloat = CaptureAnnotationDefaults.size
  var redaction: CGFloat = CaptureAnnotationDefaults.redaction
  var aspectLocked = false
  var pointSize: CGSize = .zero
  var dimensionUnit = "pt"
  var canUndo = false
  var canRedo = false
  var hasSelection = false
  private var stepCount = 0

  func nextStepLabel() -> String {
    stepCount += 1
    return "\(stepCount)"
  }

  func setAsDefaultStyle() {
    CaptureAnnotationDefaults.store(
      color: selectedColor,
      opacity: opacity,
      thickness: thickness,
      size: size,
      redaction: redaction
    )
  }
}

@MainActor
enum CaptureAnnotationDefaults {
  private static let storageKey = "captureAnnotationDefaultStyle"

  static var color: CodableColor { stored?.color ?? AnnotationPresets.defaultColor }
  static var opacity: CGFloat { stored?.opacity ?? 1 }
  static var thickness: CGFloat { stored?.thickness ?? AnnotationPresets.defaultStrokeWidth }
  static var size: CGFloat { stored?.size ?? AnnotationPresets.defaultFontSize }
  static var redaction: CGFloat { stored?.redaction ?? AnnotationPresets.defaultRedactionStrength }

  static func store(color: CodableColor, opacity: CGFloat, thickness: CGFloat, size: CGFloat, redaction: CGFloat) {
    let style = StoredStyle(color: color, opacity: opacity, thickness: thickness, size: size, redaction: redaction)
    guard let data = try? JSONEncoder().encode(style) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
  }

  private struct StoredStyle: Codable {
    let color: CodableColor
    let opacity: CGFloat
    let thickness: CGFloat
    let size: CGFloat
    var redaction: CGFloat?
  }

  private static var stored: StoredStyle? {
    guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
    return try? JSONDecoder().decode(StoredStyle.self, from: data)
  }
}
