import AppKit
import CoreGraphics
import Foundation

@MainActor
final class PinnedImageManager {
  static let shared = PinnedImageManager()

  private var windows: [PinnedImageWindow] = []
  private var didRestore = false

  private init() {}

  func pin(_ image: CGImage, displayID: CGDirectDisplayID, near point: CGPoint? = nil) {
    guard NSScreen.screen(for: displayID) != nil else { return }
    guard let pngData = try? ImageExporter.pngData(from: image) else { return }
    let window = PinnedImageWindow(
      image: image,
      pngData: pngData,
      displayID: displayID,
      pinID: UUID().uuidString
    )
    register(window)
    window.present(near: point)
    persist()
  }

  func restoreIfNeeded() {
    guard !didRestore else { return }
    didRestore = true

    let stored = StateService.shared.pinnedImages
    var survivors: [PinnedImageData] = []
    for item in stored {
      guard NSScreen.screen(for: item.displayID) != nil else { continue }
      guard let image = ImageExporter.cgImage(fromPNG: item.png) else { continue }
      let window = PinnedImageWindow(
        image: image,
        pngData: item.png,
        displayID: item.displayID,
        pinID: item.id
      )
      register(window)
      window.setFrame(
        NSRect(x: item.x, y: item.y, width: item.width, height: item.height),
        display: false
      )
      window.orderFrontRegardless()
      survivors.append(item)
    }

    if survivors.count != stored.count {
      StateService.shared.pinnedImages = survivors
    }
  }

  private func register(_ window: PinnedImageWindow) {
    window.onClose = { [weak self] id in
      self?.remove(id)
    }
    window.onFrameChange = { [weak self] _ in
      self?.persist()
    }
    windows.append(window)
  }

  private func remove(_ id: String) {
    windows.removeAll { $0.pinID == id }
    persist()
  }

  private func persist() {
    StateService.shared.pinnedImages = windows.map { window in
      PinnedImageData(
        id: window.pinID,
        displayID: window.displayID,
        x: window.frame.origin.x,
        y: window.frame.origin.y,
        width: window.frame.width,
        height: window.frame.height,
        png: window.pngData
      )
    }
  }
}
