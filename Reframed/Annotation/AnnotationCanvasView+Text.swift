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
    let host = textEditorHost()
    if textScrollView.superview !== host {
      textScrollView.removeFromSuperview()
      host?.addSubview(textScrollView)
    }
  }

  func visibleCanvasRect() -> CGRect {
    guard let container = superview else { return bounds }
    let containerRect = CGRect(origin: CGPoint(x: -frame.origin.x, y: -frame.origin.y), size: container.bounds.size)
    return containerRect.intersection(bounds)
  }

  func textEditorHost() -> NSView? {
    superview?.superview ?? superview
  }

  func textEditorArea() -> CGRect {
    guard let host = textEditorHost() else { return bounds.insetBy(dx: 8, dy: 8) }
    return convert(host.bounds, from: host).intersection(bounds).insetBy(dx: 8, dy: 8)
  }

  func scrollerWidth() -> CGFloat {
    guard textScrollView.scrollerStyle == .legacy else { return 0 }
    return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
  }

  func textEditorContentWidth() -> CGFloat {
    let capture = visibleCanvasRect()
    let boxWidth = min(AnnotationPresets.defaultTextEditorWidth, max(capture.width, 1))
    return max(boxWidth - scrollerWidth(), 1)
  }

  func textEditorTextWidth() -> CGFloat {
    max(textEditorContentWidth() - AnnotationPresets.defaultTextEditorPadding * 2, 1)
  }

  func textEditorBox(required: CGFloat, minimum: CGFloat) -> CGRect {
    let capture = visibleCanvasRect()
    let area = textEditorArea()
    let width = min(AnnotationPresets.defaultTextEditorWidth, max(capture.width, 1))
    let x = min(max(textEditorOrigin.x, capture.minX), max(capture.minX, capture.maxX - width))
    let below = max(textEditorOrigin.y - area.minY, 0)
    let above = max(area.maxY - textEditorOrigin.y, 0)
    let growsDown = below >= above
    let room = growsDown ? below : above
    let height = min(max(required, min(minimum, room)), max(room, 1))
    let top = growsDown ? textEditorOrigin.y : textEditorOrigin.y + height
    return CGRect(x: x, y: top - height, width: width, height: height)
  }

  func layoutTextEditor() {
    guard pendingText != nil else { return }
    let padding = AnnotationPresets.defaultTextEditorPadding
    let fontSize = Self.textEditorPointSize(model.fontSize, scale: currentLayout().scale)
    let contentWidth = textEditorContentWidth()
    let textWidth = textEditorTextWidth()
    var drawn = AnnotationTextLayout.boxSize(
      text: textEditor.string,
      fontSize: fontSize,
      width: textWidth
    ).height
    if let layoutManager = textEditor.layoutManager, let textContainer = textEditor.textContainer {
      layoutManager.ensureLayout(for: textContainer)
      drawn = max(drawn, layoutManager.usedRect(for: textContainer).height)
    }
    let required = drawn + padding * 2
    let minimum = AnnotationTextLayout.lineHeight(fontSize: fontSize) + padding * 2
    let box = textEditorBox(required: required, minimum: minimum)
    textEditor.font = AnnotationTextLayout.nsFont(size: fontSize)
    textEditor.textColor = NSColor(cgColor: model.strokeColor.cgColor)
    textScrollView.frame = textEditorHost().map { convert(box, to: $0) } ?? box
    textEditor.frame = CGRect(x: 0, y: 0, width: contentWidth, height: max(required, box.height))
    pendingText = PendingText(anchor: sourcePoint(CGPoint(x: box.minX, y: box.maxY)))
  }

  func endTextEditing(commit shouldCommit: Bool) {
    guard let pending = pendingText else { return }
    pendingText = nil
    let layout = currentLayout()
    let text = textEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourceWidth = textEditorTextWidth() / max(layout.scale, 0.0001)
    textEditor.delegate = nil
    textScrollView.removeFromSuperview()
    guard shouldCommit, !text.isEmpty, layout.scale > 0 else {
      window?.makeFirstResponder(self)
      return
    }
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
