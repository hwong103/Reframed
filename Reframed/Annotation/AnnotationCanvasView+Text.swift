import AppKit
import CoreGraphics

extension AnnotationCanvasView {
  struct TextEditorGeometry {
    let viewportWidth: CGFloat
    let documentWidth: CGFloat
    let textWidth: CGFloat
  }

  static func textEditorPointSize(_ base: CGFloat, scale: CGFloat) -> CGFloat {
    max(1, base * scale)
  }

  func beginTextEditing(at source: CGPoint) {
    beginTextEditing(at: source, replacing: nil)
  }

  func beginTextEditing(existing item: AnnotationItem) {
    beginTextEditing(at: item.start, replacing: item)
  }

  func beginTextEditing(at source: CGPoint, replacing item: AnnotationItem?) {
    endTextEditing(commit: true)
    editingTextItem = item
    let anchor = item?.start ?? source
    pendingText = PendingText(anchor: anchor)
    textEditorOrigin = viewPoint(anchor)
    configureTextEditor()
    textEditor.string = item?.style.text ?? ""
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

  func textEditorGeometry() -> TextEditorGeometry {
    let scale = max(currentLayout().scale, 0.0001)
    let padding = AnnotationPresets.defaultTextEditorPadding
    if let existing = editingTextItem {
      let textWidth = max(existing.bounds.width * scale - padding * 2, 1)
      let documentWidth = textWidth + padding * 2
      let area = textEditorArea()
      return TextEditorGeometry(
        viewportWidth: min(documentWidth + scrollerWidth(), max(area.width, 1)),
        documentWidth: documentWidth,
        textWidth: textWidth
      )
    }
    let capture = visibleCanvasRect()
    let boxWidth = min(AnnotationPresets.defaultTextEditorWidth, max(capture.width, 1))
    let documentWidth = max(boxWidth - scrollerWidth(), 1)
    return TextEditorGeometry(
      viewportWidth: boxWidth,
      documentWidth: documentWidth,
      textWidth: max(documentWidth - padding * 2, 1)
    )
  }

  func textEditorBox(required: CGFloat, minimum: CGFloat, viewportWidth: CGFloat, within horizontal: CGRect) -> CGRect {
    let area = textEditorArea()
    let width = max(viewportWidth, 1)
    let x = min(max(textEditorOrigin.x, horizontal.minX), max(horizontal.minX, horizontal.maxX - width))
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
    let existing = editingTextItem
    let baseFontSize = existing?.style.fontSize ?? model.fontSize
    let fontSize = Self.textEditorPointSize(baseFontSize, scale: currentLayout().scale)
    let geometry = textEditorGeometry()
    var drawn = AnnotationTextLayout.boxSize(
      text: textEditor.string,
      fontSize: fontSize,
      width: geometry.textWidth
    ).height
    if let layoutManager = textEditor.layoutManager, let textContainer = textEditor.textContainer {
      layoutManager.ensureLayout(for: textContainer)
      drawn = max(drawn, layoutManager.usedRect(for: textContainer).height)
    }
    let required = drawn + padding * 2
    let minimum = AnnotationTextLayout.lineHeight(fontSize: fontSize) + padding * 2
    let box = textEditorBox(
      required: required,
      minimum: minimum,
      viewportWidth: geometry.viewportWidth,
      within: existing == nil ? visibleCanvasRect() : textEditorArea()
    )
    textEditor.font = AnnotationTextLayout.nsFont(size: fontSize)
    textEditor.textColor = NSColor(cgColor: (existing?.style.strokeColor ?? model.strokeColor).cgColor)
    textScrollView.hasHorizontalScroller = geometry.documentWidth > box.width + 0.5
    textScrollView.frame = textEditorHost().map { convert(box, to: $0) } ?? box
    textEditor.frame = CGRect(x: 0, y: 0, width: geometry.documentWidth, height: max(required, box.height))
    if existing == nil {
      pendingText = PendingText(anchor: sourcePoint(CGPoint(x: box.minX, y: box.maxY)))
    }
  }

  func endTextEditing(commit shouldCommit: Bool) {
    guard let pending = pendingText else { return }
    let existing = editingTextItem
    let layout = currentLayout()
    let text = textEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourceWidth =
      existing.map { max($0.bounds.width, 1) }
      ?? max(textEditorGeometry().textWidth / max(layout.scale, 0.0001), 1)
    pendingText = nil
    editingTextItem = nil
    textEditor.delegate = nil
    textScrollView.removeFromSuperview()
    guard shouldCommit, !text.isEmpty, layout.scale > 0 else {
      window?.makeFirstResponder(self)
      return
    }
    let style = existing?.style ?? model.makeStyle(for: .text)
    let size = AnnotationTextLayout.boxSize(text: text, fontSize: style.fontSize, width: sourceWidth)
    let height = existing.map { max($0.bounds.height, size.height) } ?? size.height
    var item = AnnotationItem(
      id: existing?.id ?? UUID(),
      kind: .text,
      style: style,
      start: pending.anchor,
      end: pending.anchor
    )
    item.style.text = text
    item.end = CGPoint(x: pending.anchor.x + sourceWidth, y: pending.anchor.y + height)
    let target = existing?.id
    model.commit { document in
      if let target, document.item(id: target) != nil {
        document.replace(id: target, with: item)
      } else {
        document.append(item)
      }
    }
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
