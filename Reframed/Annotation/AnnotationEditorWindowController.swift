import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class AnnotationEditorWindowController: NSObject, NSWindowDelegate {
  private static var current: AnnotationEditorWindowController?
  private let model: AnnotationEditorModel
  private var window: NSWindow?
  private var canvas: AnnotationCanvasView?

  static func present(image: CGImage, reference: SourceImageReference) {
    current?.close()
    let controller = AnnotationEditorWindowController(image: image, reference: reference)
    current = controller
    controller.show()
  }

  private init(image: CGImage, reference: SourceImageReference) {
    self.model = AnnotationEditorModel(image: image, reference: reference)
    super.init()
  }

  func close() {
    window?.delegate = nil
    window?.close()
    teardown()
  }

  func windowWillClose(_ notification: Notification) {
    teardown()
  }

  private func teardown() {
    model.changeHandler = nil
    canvas = nil
    window = nil
    if Self.current === self {
      Self.current = nil
    }
  }

  private func show() {
    let canvasView = AnnotationCanvasView(model: model)
    canvas = canvasView
    canvasView.translatesAutoresizingMaskIntoConstraints = false
    canvasView.setContentHuggingPriority(.defaultLow, for: .vertical)
    canvasView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    canvasView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let hosting = NSHostingView(rootView: AnnotationToolbarView(model: model, commands: makeCommands()))
    hosting.sizingOptions = [.intrinsicContentSize]
    hosting.setContentHuggingPriority(.required, for: .vertical)
    hosting.setContentCompressionResistancePriority(.required, for: .vertical)

    let stack = NSStackView(views: [hosting, canvasView])
    stack.orientation = .vertical
    stack.alignment = .width
    stack.spacing = 0
    stack.distribution = .fill
    stack.translatesAutoresizingMaskIntoConstraints = false

    let metrics = metrics(toolbarHeight: hosting.fittingSize.height)
    NSLayoutConstraint.activate([
      canvasView.widthAnchor.constraint(greaterThanOrEqualToConstant: metrics.canvas.width),
      canvasView.heightAnchor.constraint(greaterThanOrEqualToConstant: metrics.canvas.height),
    ])

    let container = NSView(frame: NSRect(origin: .zero, size: metrics.content))
    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      stack.topAnchor.constraint(equalTo: container.topAnchor),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: metrics.content),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.title = "Annotate"
    window.contentView = container
    window.contentMinSize = metrics.content
    window.setContentSize(metrics.content)
    window.delegate = self
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(canvasView)
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
  }

  private func makeCommands() -> AnnotationToolbarCommands {
    AnnotationToolbarCommands(
      copy: { [weak self] in self?.copyRendered() },
      saveAndCopy: { [weak self] in self?.saveRendered() },
      close: { [weak self] in self?.close() }
    )
  }

  private func metrics(toolbarHeight: CGFloat) -> (canvas: CGSize, content: CGSize) {
    let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1400, height: 900)
    let limit = CGSize(
      width: min(1180, visible.width - 80),
      height: min(700, visible.height - toolbarHeight - 80)
    )
    let pixel = model.pixelSize
    let scale = min(1, limit.width / max(pixel.width, 1), limit.height / max(pixel.height, 1))
    let scaled = CGSize(width: pixel.width * scale, height: pixel.height * scale)
    let canvas = CGSize(width: ceil(max(scaled.width, 360)), height: ceil(max(scaled.height, 240)))
    return (canvas, CGSize(width: canvas.width, height: canvas.height + ceil(toolbarHeight)))
  }

  private func copyRendered() {
    guard let image = model.renderedImage() else { return }
    if ImageExporter.copyToPasteboard(image) {
      RecentCaptureStore.shared.record(image: image, filename: ScreenshotNaming.previewName())
      ScreenshotFeedbackWindow.show("Copied to clipboard", near: NSEvent.mouseLocation)
    } else {
      present("Could not copy the screenshot to the clipboard.")
    }
  }

  private func saveRendered() {
    guard let image = model.renderedImage() else { return }
    let url = ScreenshotNaming.destinationURL()
    do {
      try ImageExporter.writePNG(image, to: url)
      RecentCaptureStore.shared.record(image: image, filename: url.lastPathComponent)
      let copied = ImageExporter.copyToPasteboard(image, fileURL: url)
      ScreenshotFeedbackWindow.show(
        copied ? "Saved" : "Saved, but the clipboard copy failed",
        detail: url.lastPathComponent,
        near: NSEvent.mouseLocation
      )
    } catch {
      present(error.localizedDescription)
    }
  }

  private func present(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Could not save annotation"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
