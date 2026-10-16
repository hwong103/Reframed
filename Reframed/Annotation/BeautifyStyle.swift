import CoreGraphics
import Foundation

struct BeautifyStyle: Codable, Sendable, Equatable {
  var padding: CGFloat = 0
  var cornerRadius: CGFloat = 0
  var shadowOpacity: CGFloat = 0
  var shadowRadius: CGFloat = 0
  var shadowOffset: CGFloat = 0
  var background: BackgroundStyle = .none

  var isActive: Bool {
    padding > 0 || cornerRadius > 0 || shadowOpacity > 0 || background != .none
  }

  static let off = BeautifyStyle()

  static let standard = BeautifyStyle(
    padding: 48,
    cornerRadius: 14,
    shadowOpacity: 0.3,
    shadowRadius: 28,
    shadowOffset: 12,
    background: .gradient(1)
  )
}
