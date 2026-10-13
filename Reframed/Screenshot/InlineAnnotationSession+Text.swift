import CoreGraphics

extension InlineAnnotationSession {
  func captureText() {
    guard !isReadingText else { return }
    guard let rendered = renderedSelection() else { return end() }
    isReadingText = true
    handlers.captureText(rendered, selection) { [weak self] outcome in
      guard let self else { return }
      self.isReadingText = false
    }
  }
}
