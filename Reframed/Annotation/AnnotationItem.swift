import CoreGraphics
import Foundation

enum AnnotationToolKind: String, CaseIterable, Codable, Sendable {
  case arrow
  case rectangle
  case ellipse
  case line
  case pen
  case highlighter
  case text
  case blur
  case pixelate
  case crop

  static var allCases: [AnnotationToolKind] {
    [.arrow, .rectangle, .ellipse, .line, .pen, .highlighter, .text, .blur, .crop]
  }
}

struct AnnotationStyle: Codable, Sendable, Equatable {
  var strokeColor: CodableColor
  var fillColor: CodableColor?
  var strokeWidth: CGFloat
  var opacity: CGFloat
  var blurRadius: CGFloat
  var fontSize: CGFloat
  var text: String

  init(
    strokeColor: CodableColor,
    fillColor: CodableColor? = nil,
    strokeWidth: CGFloat = 3,
    opacity: CGFloat = 1,
    blurRadius: CGFloat = 12,
    fontSize: CGFloat = 18,
    text: String = ""
  ) {
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.strokeWidth = strokeWidth
    self.opacity = opacity
    self.blurRadius = blurRadius
    self.fontSize = fontSize
    self.text = text
  }
}

struct AnnotationItem: Codable, Sendable, Equatable, Identifiable {
  let id: UUID
  var kind: AnnotationToolKind
  var style: AnnotationStyle
  var start: CGPoint
  var end: CGPoint
  var points: [CGPoint]

  init(
    id: UUID = UUID(),
    kind: AnnotationToolKind,
    style: AnnotationStyle,
    start: CGPoint = .zero,
    end: CGPoint = .zero,
    points: [CGPoint] = []
  ) {
    self.id = id
    self.kind = kind
    self.style = style
    self.start = start
    self.end = end
    self.points = points
  }

  var bounds: CGRect {
    CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )
  }

  var polyline: [CGPoint] {
    if points.count >= 2 {
      return points
    }
    return [start, end]
  }
}
