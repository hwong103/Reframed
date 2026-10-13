import AppKit
import CoreGraphics

extension AnnotationCanvasView {
  func beginTextEditing(at source: CGPoint) {
    endTextEditing(commit: true)
    pendingText = PendingText(anchor: source)
    let layout = currentLayout()
    let height = max(22, model.fontSize * layout.scale + 10)
    let point = viewPoint(source)
    textField.frame = CGRect(x: point.x, y: point.y - height, width: 220, height: height)
    textField.font = .systemFont(ofSize: max(9, model.fontSize * layout.scale))
    textField.textColor = NSColor(cgColor: model.strokeColor.cgColor)
    textField.stringValue = ""
    textField.isBordered = true
    textField.bezelStyle = .roundedBezel
    textField.focusRingType = .default
    textField.target = self
    textField.action = #selector(commitTextEditing)
    textField.delegate = self
    if textField.superview == nil {
      addSubview(textField)
    }
    window?.makeFirstResponder(textField)
  }

  func endTextEditing(commit shouldCommit: Bool) {
    guard let pending = pendingText else { return }
    pendingText = nil
    let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    textField.delegate = nil
    textField.removeFromSuperview()
    guard shouldCommit, !text.isEmpty else {
      window?.makeFirstResponder(self)
      return
    }
    var item = AnnotationItem(
      kind: .text,
      style: model.makeStyle(for: .text),
      start: pending.anchor,
      end: pending.anchor
    )
    item.style.text = text
    item.end = CGPoint(x: pending.anchor.x + textWidth(text), y: pending.anchor.y + model.fontSize)
    model.commit { $0.append(item) }
    model.select(item.id)
    window?.makeFirstResponder(self)
  }

  @objc func commitTextEditing() {
    endTextEditing(commit: true)
  }

  func textWidth(_ text: String) -> CGFloat {
    let font = NSFont.systemFont(ofSize: max(1, model.fontSize))
    return (text as NSString).size(withAttributes: [.font: font]).width
  }

  func placeStepStamp(_ text: String, at source: CGPoint) {
    var item = AnnotationItem(kind: .text, style: model.makeStyle(for: .text), start: source, end: source)
    item.style.text = text
    item.end = CGPoint(x: source.x + textWidth(text), y: source.y + model.fontSize)
    model.commit { $0.append(item) }
    model.select(item.id)
    needsDisplay = true
  }
}

extension AnnotationCanvasView: NSTextFieldDelegate {
  func controlTextDidEndEditing(_ obj: Notification) {
    endTextEditing(commit: true)
  }
}
