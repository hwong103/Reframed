import AppKit

extension SelectionOverlayView {
  var isWindowPickEnabled: Bool {
    request.hoverTargetsEnabled && hoverProvider != nil
  }

  var isAutoSelection: Bool {
    isFullDisplayInitial || committedWindowID != nil
  }

  func clearWindowSelection() {
    selectedWindowIDs.removeAll()
    selectedWindowRects.removeAll()
  }

  func captureHoveredWindow(at point: CGPoint) {
    clearWindowSelection()
    commitHoveredTarget(at: point)
    captureImmediately()
  }

  func toggleWindowSelection(at point: CGPoint) {
    guard
      let target = hoverProvider?.target(at: cgPoint(from: point)),
      let local = localRect(for: target)
    else {
      return
    }

    if selectedWindowIDs.contains(target.windowID) {
      selectedWindowIDs.removeAll { $0 == target.windowID }
      selectedWindowRects[target.windowID] = nil
    } else {
      selectedWindowIDs.append(target.windowID)
      selectedWindowRects[target.windowID] = local
    }

    hoverTarget = target
    committedWindowID = target.windowID
    selectionRect = local
    isFullDisplayInitial = false
    hoverSuppressed = false
    needsDisplay = true
    updateControlsPanel()
  }

  func applyFullDisplaySelection() {
    selectionRect = bounds
    isFullDisplayInitial = true
    committedWindowID = nil
    hoverTarget = nil
    needsDisplay = true
    updateControlsPanel()
  }

  var windowStatus: String? {
    guard committedWindowID != nil else { return nil }
    return optionsHeld ? "No shadow (Option held)" : "Sharp \u{00b7} shadow if occluded"
  }

  var windowSelectionNote: String? {
    let count = selectedWindowIDs.count
    guard count > 0 else { return nil }
    return "\(count) \(count == 1 ? "window" : "windows") selected \u{00b7} Enter to capture"
  }
}
