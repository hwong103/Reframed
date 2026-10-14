import AppKit

extension InlineAnnotationSession {
  func applyBeautify() {
    canvas.beautifyScale = selection.backingScaleFactor > 0 ? selection.backingScaleFactor : 1
    canvas.beautifyStyle = state.beautifyEnabled ? .standard : .off
    canvas.needsDisplay = true
  }

  func toggleBeautify() {
    state.beautifyEnabled.toggle()
    applyBeautify()
    onBeautifyChange?()
  }

  func handleKey(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

    if flags.contains(.command) {
      switch key {
      case "s":
        flags.contains(.shift) ? saveAndCopy() : save()
        return true
      case "z":
        flags.contains(.shift) ? redo() : undo()
        return true
      default:
        return false
      }
    }

    guard flags.isEmpty else { return false }

    switch event.keyCode {
    case 53:
      cancel()
      return true
    case 36, 49, 76:
      copy()
      return true
    case 51, 117:
      deleteSelected()
      return true
    default:
      break
    }

    if let tool = CaptureAnnotationTool.tool(forKey: key) {
      selectTool(tool)
      return true
    }

    switch key {
    case "b":
      toggleBeautify()
    case "o":
      captureText()
    case "t":
      pin()
    case "w":
      openInWindow()
    case "p":
      openInPreview()
    case "s":
      scrollingCapture()
    default:
      return false
    }
    return true
  }
}
