import CoreGraphics
import Foundation

extension AnnotationRenderer {
  static func beautified(_ image: CGImage, style: BeautifyStyle, scale: CGFloat) -> CGImage? {
    guard style.isActive else { return image }
    guard image.width > 0, image.height > 0 else { return nil }
    let density = max(scale, 1)
    let padding = (style.padding * density).rounded()
    let radius = (style.cornerRadius * density).rounded()
    let shadowRadius = (style.shadowRadius * density).rounded()
    let shadowOffset = (style.shadowOffset * density).rounded()
    let bleed = style.shadowOpacity > 0 ? shadowRadius + shadowOffset : 0
    let width = Int((CGFloat(image.width) + (padding + bleed) * 2).rounded())
    let height = Int((CGFloat(image.height) + (padding + bleed) * 2).rounded())
    guard width > 0, height > 0, let context = bitmapContext(nil, width: width, height: height) else {
      return nil
    }
    let canvas = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    drawBeautifyBackground(style.background, in: context, canvas: canvas)
    let frame = CGRect(
      x: bleed + padding,
      y: bleed + padding,
      width: CGFloat(image.width),
      height: CGFloat(image.height)
    )
    let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if style.shadowOpacity > 0 {
      context.saveGState()
      context.addPath(path)
      context.setFillColor(black(alpha: 1))
      context.setShadow(
        offset: CGSize(width: 0, height: -shadowOffset),
        blur: shadowRadius,
        color: black(alpha: style.shadowOpacity)
      )
      context.fillPath()
      context.restoreGState()
    }
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.interpolationQuality = .none
    context.draw(image, in: frame)
    context.restoreGState()
    return context.makeImage()
  }

  private static func black(alpha: CGFloat) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [0, 0, 0, alpha]) ?? CGColor(gray: 0, alpha: alpha)
  }

  static func drawBeautifyBackground(_ style: BackgroundStyle, in context: CGContext, canvas: CGRect) {
    switch style {
    case .none, .image:
      return
    case .solidColor(let color):
      context.setFillColor(cgColor(color))
      context.fill(canvas)
    case .gradient(let id):
      guard let preset = GradientPresets.preset(for: id) else { return }
      let colors = preset.cgColors
      guard colors.count >= 2,
        let gradient = CGGradient(
          colorsSpace: colorSpace,
          colors: colors as CFArray,
          locations: nil
        )
      else {
        return
      }
      let start = CGPoint(
        x: canvas.minX + canvas.width * preset.cgStartPoint.x,
        y: canvas.minY + canvas.height * preset.cgStartPoint.y
      )
      let end = CGPoint(
        x: canvas.minX + canvas.width * preset.cgEndPoint.x,
        y: canvas.minY + canvas.height * preset.cgEndPoint.y
      )
      context.saveGState()
      context.clip(to: canvas)
      context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
      context.restoreGState()
    }
  }
}
