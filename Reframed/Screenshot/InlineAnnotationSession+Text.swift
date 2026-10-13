import CoreGraphics

extension InlineAnnotationSession {
  func captureText() {
    guard !isReadingText else { return }
    guard let rendered = renderedSelection() else { return end() }
    isReadingText = true
    let detailed = retryArmed
    handlers.captureText(rendered, selection, detailed) { [weak self] outcome in
      guard let self else { return }
      self.isReadingText = false
      self.retryArmed = outcome == .empty
    }
  }
}
