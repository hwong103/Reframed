import AppKit
import CoreGraphics

extension AnnotationCanvasView {
  static func textEditorPointSize(_ base: CGFloat, scale: CGFloat) -> CGFloat {
    max(9, base * scale)
  }

  func beginTextEditing(at source: CGPoint) {
    endTextEditing(commit: true)
    pendingText = PendingText(anchor: source)
    let anchor = viewPoint(source)
    let padding = AnnotationPresets.defaultTextEditorPadding
    let width = AnnotationPresets.defaultTextEditorWidth
    let fontSize = Self.textEditorPointSize(model.fontSize, scale: currentLayout().scale)
    let textWidth = width - padding * 2
    let height = AnnotationTextLayout.boxSize(text: "", fontSize: fontSize, width: textWidth).height + padding * 2
    textEditor.frame = CGRect(x: anchor.x, y: anchor.y - height, width: width, height: height)
    textEditor.font = .systemFont(ofSize: fontSize)
    textEditor.textColor = NSColor(cgColor: model.strokeColor.cgColor)
    textEditor.textContainerInset = NSSize(width: padding, height: padding)
    textEditor.textContainer?.lineFragmentPadding = 0
    textEditor.textContainer?.widthTracksTextView = true
    textEditor.textContainer?.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
    textEditor.minSize = NSSize(width: width, height: 0)
    textEditor.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    textEditor.isVerticallyResizable = true
    textEditor.isHorizontallyResizable = false
    textEditor.string = ""
    textEditor.delegate = self
    if textEditor.superview == nil {
      textEditor.autoresizingMask = []
      addSubview(textEditor)
    }
    window?.makeFirstResponder(textEditor)
  }

  func layoutTextEditor() {
    guard pendingText != nil else { return }
    let padding = AnnotationPresets.defaultTextEditorPadding
    let fontSize = Self.textEditorPointSize(model.fontSize, scale: currentLayout().scale)
    let textWidth = AnnotationPresets.defaultTextEditorWidth - padding * 2
    let height =
      AnnotationTextLayout.boxSize(
        text: textEditor.string,
        fontSize: fontSize,
        width: textWidth
      ).height + padding * 2
    let frame = textEditor.frame
    textEditor.frame = CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
  }

  func endTextEditing(commit shouldCommit: Bool) {
    guard let pending = pendingText else { return }
    pendingText = nil
    let layout = currentLayout()
    let text = textEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
    textEditor.delegate = nil
    textEditor.removeFromSuperview()
    guard shouldCommit, !text.isEmpty, layout.scale > 0 else {
      window?.makeFirstResponder(self)
      return
    }
    let width = (AnnotationPresets.defaultTextEditorWidth - AnnotationPresets.defaultTextEditorPadding * 2) / layout.scale
    let size = AnnotationTextLayout.boxSize(text: text, fontSize: model.fontSize, width: width)
    var item = AnnotationItem(
      kind: .text,
      style: model.makeStyle(for: .text),
      start: pending.anchor,
      end: pending.anchor
    )
    item.style.text = text
    item.end = CGPoint(x: pending.anchor.x + size.width, y: pending.anchor.y + size.height)
    model.commit { $0.append(item) }
    model.select(item.id)
    window?.makeFirstResponder(self)
  }

  func textWidth(_ text: String) -> CGFloat {
    AnnotationTextLayout.lineWidth(text: text, fontSize: model.fontSize)
  }

  func placeStepStamp(_ text: String, at source: CGPoint) {
    var item = AnnotationItem(kind: .text, style: model.makeStyle(for: .text), start: source, end: source)
    item.style.text = text
    item.end = CGPoint(
      x: source.x + textWidth(text),
      y: source.y + AnnotationTextLayout.lineHeight(fontSize: model.fontSize)
    )
    model.commit { $0.append(item) }
    model.select(item.id)
    needsDisplay = true
  }
}

extension AnnotationCanvasView: NSTextViewDelegate {
  func textDidChange(_ notification: Notification) {
    layoutTextEditor()
  }

  func textDidEndEditing(_ notification: Notification) {
    endTextEditing(commit: true)
  }

  func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      endTextEditing(commit: true)
      return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      endTextEditing(commit: false)
      return true
    }
    return false
  }
}
