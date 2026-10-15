import AppKit
import CoreGraphics
import CoreText
import Foundation

enum AnnotationTextAnchor {
  case top
  case bottom
}

enum AnnotationTextLayout {
  struct Layout: Equatable {
    let lines: Int
    let height: CGFloat
  }

  static let fontName = "Helvetica"

  static func font(size: CGFloat) -> CTFont {
    let pointSize = max(1, size)
    return CTFontCreateWithName(fontName as CFString, pointSize, nil)
  }

  static func nsFont(size: CGFloat) -> NSFont {
    let pointSize = max(1, size)
    return NSFont(name: fontName, size: pointSize) ?? NSFont.systemFont(ofSize: pointSize)
  }

  static func attributedText(_ text: String, fontSize: CGFloat, color: CGColor? = nil) -> NSAttributedString {
    var attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font(size: fontSize)
    ]
    if let color {
      attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
    }
    return NSAttributedString(string: text, attributes: attributes)
  }

  static func layout(text: String, fontSize: CGFloat, width: CGFloat) -> Layout {
    let attributed = attributedText(text, fontSize: fontSize)
    let lineHeight = lineHeight(fontSize: fontSize)
    guard attributed.length > 0 else {
      return Layout(lines: 0, height: lineHeight)
    }
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let wrap = max(width, 1)
    var fit = CFRange()
    var height = ceil(
      CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: 0),
        nil,
        CGSize(width: wrap, height: CGFloat.greatestFiniteMagnitude),
        &fit
      ).height
    )
    for _ in 0..<8 {
      let path = CGPath(rect: CGRect(x: 0, y: 0, width: wrap, height: height), transform: nil)
      let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
      let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
      let visible = CTFrameGetVisibleStringRange(frame)
      if visible.length >= attributed.length || lines.isEmpty {
        return Layout(lines: lines.count, height: max(height, lineHeight))
      }
      height += lineHeight
    }
    return Layout(lines: 0, height: max(height, lineHeight))
  }

  static func lineHeight(fontSize: CGFloat) -> CGFloat {
    let font = font(size: fontSize)
    return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
  }

  static func lineWidth(text: String, fontSize: CGFloat) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let line = CTLineCreateWithAttributedString(attributedText(text, fontSize: fontSize))
    return ceil(CTLineGetTypographicBounds(line, nil, nil, nil))
  }

  static func boxSize(text: String, fontSize: CGFloat, width: CGFloat) -> CGSize {
    let wrap = max(width, 1)
    let layout = layout(text: text, fontSize: fontSize, width: wrap)
    return CGSize(width: wrap, height: max(layout.height, lineHeight(fontSize: fontSize)))
  }

  static func fitted(_ item: AnnotationItem, anchor: AnnotationTextAnchor = .top) -> AnnotationItem {
    guard item.kind == .text else { return item }
    let box = item.bounds.standardized
    let width = max(box.width, 1)
    let needed = boxSize(text: item.style.text, fontSize: item.style.fontSize, width: width).height
    let height = max(box.height, needed)
    let minY = anchor == .top ? box.minY : box.maxY - height
    var result = item
    result.start = CGPoint(x: box.minX, y: minY)
    result.end = CGPoint(x: box.minX + width, y: minY + height)
    return result
  }

  static func frame(text: String, fontSize: CGFloat, color: CGColor, size: CGSize) -> CTFrame? {
    guard !text.isEmpty, size.width >= 1, size.height >= 1 else { return nil }
    let attributed = attributedText(text, fontSize: fontSize, color: color)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
    return CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
  }
}
