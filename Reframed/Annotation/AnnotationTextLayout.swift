import CoreGraphics
import CoreText
import Foundation

enum AnnotationTextLayout {
  struct Layout: Equatable {
    let lines: Int
    let height: CGFloat
  }

  static func font(size: CGFloat) -> CTFont {
    let pointSize = max(1, size)
    return CTFontCreateUIFontForLanguage(.system, pointSize, nil)
      ?? CTFontCreateWithName("Helvetica" as CFString, pointSize, nil)
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
    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
    let limit = Double(max(width, 1))
    var offset = 0
    var lines = 0
    var height: CGFloat = 0
    while offset < attributed.length {
      let count = CTTypesetterSuggestLineBreak(typesetter, offset, limit)
      guard count > 0 else { break }
      let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: count))
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      height += ascent + descent + leading
      lines += 1
      offset += count
    }
    guard lines > 0 else {
      return Layout(lines: 0, height: lineHeight)
    }
    return Layout(lines: lines, height: ceil(height))
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

  static func frame(text: String, fontSize: CGFloat, color: CGColor, size: CGSize) -> CTFrame? {
    guard !text.isEmpty, size.width >= 1, size.height >= 1 else { return nil }
    let attributed = attributedText(text, fontSize: fontSize, color: color)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
    return CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
  }
}
