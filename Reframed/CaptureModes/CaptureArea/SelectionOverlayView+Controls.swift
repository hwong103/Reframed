import AppKit
import SwiftUI

extension SelectionOverlayView {
  func applyExternalRect(_ newRect: CGRect) {
    selectionRect = newRect.clamped(to: bounds)
    isFullDisplayInitial = false
    committedWindowID = nil
    hoverTarget = nil
    needsDisplay = true
    updateControlsPanel()
  }

  func confirmSelection() {
    guard let rect = selectionRect, rect.width >= 10, rect.height >= 10 else {
      request.onCancel()
      return
    }

    if request.annotation != nil {
      enterAnnotationMode()
      return
    }

    guard let window = self.window else {
      request.onCancel()
      return
    }

    if let windowID = committedWindowID, let onConfirmWindow = request.onConfirmWindow {
      let windowRect = convert(rect, to: nil)
      let screenRect = window.convertToScreen(windowRect)
      onConfirmWindow(windowID, screenRect)
      return
    }

    let windowRect = convert(rect, to: nil)
    let screenRect = window.convertToScreen(windowRect)
    let midPoint = CGPoint(x: screenRect.midX, y: screenRect.midY)
    let displayID = NSScreen.screens.first { $0.frame.contains(midPoint) }?.displayID ?? CGMainDisplayID()

    let selection = SelectionRect(rect: screenRect, displayID: displayID)
    request.onConfirm(selection)
  }

  func updateControlsPanel() {
    if request.annotation != nil || annotationSession != nil {
      controlsHost?.isHidden = true
      updateAnnotationLayout()
      return
    }

    guard let rect = selectionRect else {
      controlsHost?.isHidden = true
      return
    }

    let isFirstCreate = controlsHost == nil
    if isFirstCreate {
      let view = CaptureAreaView(
        timerDelay: request.timerDelay,
        confirmTitle: request.confirmTitle,
        hint: request.hint,
        onCountdownStart: request.onCountdownStart,
        onCancel: request.onCancel,
        onConfirm: { [weak self] in self?.confirmSelection() },
        onSelectionRectChange: { [weak self] rect in self?.applyExternalRect(rect) }
      )
      let hosting = NSHostingView(rootView: view)
      addSubview(hosting)
      controlsHost = hosting
    }

    guard let hosting = controlsHost else { return }

    if isFirstCreate {
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .selectionRectChanged, object: NSValue(rect: rect))
      }
    } else {
      NotificationCenter.default.post(name: .selectionRectChanged, object: NSValue(rect: rect))
    }

    postTargetInfo(for: rect)

    let panelSize = hosting.intrinsicContentSize
    hosting.setFrameSize(panelSize)

    var panelX = rect.midX - panelSize.width / 2
    var panelY = rect.minY - panelSize.height - 16

    if panelY < bounds.minY + 8 {
      panelY = rect.maxY + 16
    }

    panelX = max(bounds.minX + 8, min(panelX, bounds.maxX - panelSize.width - 8))
    panelY = max(bounds.minY + 8, min(panelY, bounds.maxY - panelSize.height - 8))

    hosting.frame.origin = CGPoint(x: panelX, y: panelY)
    hosting.isHidden = false
  }

  private func postTargetInfo(for rect: CGRect) {
    let scale = window?.backingScaleFactor ?? 2
    let info = SelectionTargetInfo(
      title: hoverTarget?.title,
      pixelWidth: Int((rect.width * scale).rounded()),
      pixelHeight: Int((rect.height * scale).rounded())
    )
    NotificationCenter.default.post(name: .selectionTargetChanged, object: SelectionTargetInfoBox(info))
  }

  func commitHoveredTarget(at point: CGPoint) {
    if let target = hoverProvider?.target(at: cgPoint(from: point)), let local = localRect(for: target) {
      hoverTarget = target
      committedWindowID = target.windowID
      selectionRect = local
      isFullDisplayInitial = false
    } else {
      applyFullDisplaySelection()
    }
    hoverSuppressed = false
    isDragging = false
    dragOrigin = nil
    needsDisplay = true
    updateControlsPanel()
  }

  func updateHover(at point: CGPoint) {
    guard let provider = hoverProvider else { return }
    let target = provider.target(at: cgPoint(from: point))

    if let target, let local = localRect(for: target) {
      guard hoverTarget != target else { return }
      hoverTarget = target
      committedWindowID = target.windowID
      selectionRect = local
      isFullDisplayInitial = false
      needsDisplay = true
      updateControlsPanel()
      return
    }

    if hoverTarget != nil || !isFullDisplayInitial {
      hoverTarget = nil
      committedWindowID = nil
      applyFullDisplaySelection()
    }
  }

  func cgPoint(from local: CGPoint) -> CGPoint {
    let origin = window?.frame.origin ?? .zero
    return CGPoint(x: origin.x + local.x, y: NSScreen.primaryScreenHeight - (origin.y + local.y))
  }

  func localRect(for target: HoverTarget) -> CGRect? {
    let origin = window?.frame.origin ?? .zero
    let appKit = CGRect(
      x: target.bounds.origin.x,
      y: NSScreen.primaryScreenHeight - target.bounds.maxY,
      width: target.bounds.width,
      height: target.bounds.height
    )
    let local = CGRect(
      x: appKit.origin.x - origin.x,
      y: appKit.origin.y - origin.y,
      width: appKit.width,
      height: appKit.height
    )
    let clipped = local.intersection(bounds)
    return clipped.isNull || clipped.width < 1 || clipped.height < 1 ? nil : clipped
  }
}

struct SelectionTargetInfo {
  let title: String?
  let pixelWidth: Int
  let pixelHeight: Int
}

final class SelectionTargetInfoBox: NSObject {
  let info: SelectionTargetInfo

  init(_ info: SelectionTargetInfo) {
    self.info = info
  }
}
