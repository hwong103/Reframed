import AppKit
import CoreGraphics

extension AnnotationCanvasView {
  static func textEditorPointSize(_ base: CGFloat, scale: CGFloat) -> CGFloat {
    max(1, base * scale)
  }

  func beginTextEditing(at source: CGPoint) {
    endTextEditing(commit: true)
    pendingText = PendingText(anchor: source)
    textEditorOrigin = viewPoint(source)
    configureTextEditor()
    textEditor.string = ""
    layoutTextEditor()
    window?.makeFirstResponder(textEditor)
  }

  func configureTextEditor() {
    let padding = AnnotationPresets.defaultTextEditorPadding
    textEditor.isRichText = false
    textEditor.drawsBackground = true
    textEditor.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.95)
    textEditor.textContainerInset = NSSize(width: padding, height: padding)
    textEditor.textContainer?.lineFragmentPadding = 0
    textEditor.textContainer?.widthTracksTextView = true
    textEditor.isVerticallyResizable = true
    textEditor.isHorizontallyResizable = false
    textEditor.minSize = .zero
    textEditor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textEditor.autoresizingMask = []
    textEditor.delegate = self
    textScrollView.drawsBackground = false
    textScrollView.borderType = .noBorder
    textScrollView.hasVerticalScroller = true
    textScrollView.autohidesScrollers = true
    textScrollView.autoresizingMask = []
    textScrollView.wantsLayer = true
    textScrollView.layer?.borderWidth = 1
    textScrollView.layer?.borderColor = NSColor.controlAccentColor.cgColor
    textScrollView.layer?.cornerRadius = 4
    textScrollView.documentView = textEditor
    if textScrollView.superview == nil {
      addSubview(textScrollView)
    }
  }

  func visibleCanvasRect() -> CGRect {
    guard let container = superview else { return bounds }
    let containerRect = CGRect(origin: CGPoint(x: -frame.origin.x, y: -frame.origin.y), size: container.bounds.size)
    return containerRect.intersection(bounds)
  }

  func layoutTextEditor() {
    guard pendingText != nil else { return }
    let padding = AnnotationPresets.defaultTextEditorPadding
    let fontSize = Self.textEditorPointSize(model.fontSize, scale: currentLayout().scale)
    let visible = visibleCanvasRect()
    let width = min(AnnotationPresets.defaultTextEditorWidth, max(visible.width, 1))
    let textWidth = max(width - padding * 2, 1)
    let shared = AnnotationTextLayout.boxSize(
      text: textEditor.string,
      fontSize: fontSize,
      width: textWidth
    ).height
    var drawn = shared
    if let layoutManager = textEditor.layoutManager, let textContainer = textEditor.textContainer {
      layoutManager.ensureLayout(for: textContainer)
      drawn = max(drawn, layoutManager.usedRect(for: textContainer).height)
    }
    let required = drawn + padding * 2
    let minimum = AnnotationTextLayout.lineHeight(fontSize: fontSize) + padding * 2
    let x = min(max(textEditorOrigin.x, visible.minX), max(visible.minX, visible.maxX - width))
    let below = max(textEditorOrigin.y - visible.minY, 0)
    let above = max(visible.maxY - textEditorOrigin.y, 0)
    let growsDown = below >= above
    let room = growsDown ? below : above
    let height = min(max(required, min(minimum, room)), max(room, 1))
    let top = growsDown ? textEditorOrigin.y : textEditorOrigin.y + height
    let box = CGRect(x: x, y: top - height, width: width, height: height)
    textEditor.font = AnnotationTextLayout.nsFont(size: fontSize)
    textEditor.textColor = NSColor(cgColor: model.strokeColor.cgColor)
    textScrollView.frame = box
    textEditor.frame = CGRect(x: 0, y: 0, width: width, height: max(required, height))
    pendingText = PendingText(anchor: sourcePoint(CGPoint(x: box.minX, y: box.maxY)))
  }

  func endTextEditing(commit shouldCommit: Bool) {
    guard let pending = pendingText else { return }
    pendingText = nil
    let layout = currentLayout()
    let padding = AnnotationPresets.defaultTextEditorPadding
    let text = textEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
    textEditor.delegate = nil
    textScrollView.removeFromSuperview()
    guard shouldCommit, !text.isEmpty, layout.scale > 0 else {
      window?.makeFirstResponder(self)
      return
    }
    let visible = visibleCanvasRect()
    let width = min(AnnotationPresets.defaultTextEditorWidth, max(visible.width, 1))
    let sourceWidth = max(width - padding * 2, 1) / layout.scale
    let size = AnnotationTextLayout.boxSize(text: text, fontSize: model.fontSize, width: sourceWidth)
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
    let width = textWidth(text)
    let size = AnnotationTextLayout.boxSize(text: text, fontSize: model.fontSize, width: width)
    item.end = CGPoint(x: source.x + size.width, y: source.y + size.height)
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
      endTextEditing(commit: true)
      return true
    }
    return false
  }
}
