import AppKit
import CoreGraphics
import Foundation

var failures = 0

func check(_ passed: Bool, _ label: String, _ detail: String) {
  if !passed { failures += 1 }
  print("\(passed ? "PASS" : "FAIL") \(label) -- \(detail)")
}

let fontSize = AnnotationPresets.defaultFontSize
let bodyText = "Reframed annotation text should wrap to the width of its box instead of running off the edge of the selection."

func makeSource(width: Int, height: Int) -> CGImage {
  let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  return context.makeImage()!
}

struct Ink {
  var minX: CGFloat
  var minY: CGFloat
  var maxX: CGFloat
  var maxY: CGFloat
}

@MainActor
func textInk(document: AnnotationDocument, image: CGImage) -> Ink? {
  let size = AnnotationRenderer.outputSize(for: document)
  let width = Int(size.width.rounded())
  let height = Int(size.height.rounded())
  guard width > 0, height > 0 else { return nil }
  guard let context = AnnotationRenderer.bitmapContext(nil, width: width, height: height) else {
    return nil
  }
  context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  AnnotationRenderer.renderDirect(document, image: image, into: context)
  guard let bitmap = context.makeImage() else { return nil }

  var buffer = [UInt8](repeating: 0, count: width * height * 4)
  var copied = false
  buffer.withUnsafeMutableBytes { raw in
    guard
      let base = raw.baseAddress,
      let copy = CGContext(
        data: base,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: AnnotationRenderer.colorSpace,
        bitmapInfo: AnnotationRenderer.bitmapInfo
      )
    else { return }
    copy.setBlendMode(.copy)
    copy.draw(bitmap, in: CGRect(x: 0, y: 0, width: width, height: height))
    copied = true
  }
  guard copied else { return nil }

  var ink: Ink?
  for y in 0..<height {
    for x in 0..<width {
      let index = (y * width + x) * 4
      let red = Int(buffer[index])
      let green = Int(buffer[index + 1])
      let blue = Int(buffer[index + 2])
      guard red < 250 || green < 250 || blue < 250 else { continue }
      let sourceX = CGFloat(x)
      let sourceY = CGFloat(y)
      if var current = ink {
        current.minX = min(current.minX, sourceX)
        current.minY = min(current.minY, sourceY)
        current.maxX = max(current.maxX, sourceX)
        current.maxY = max(current.maxY, sourceY)
        ink = current
      } else {
        ink = Ink(minX: sourceX, minY: sourceY, maxX: sourceX, maxY: sourceY)
      }
    }
  }
  return ink
}

func describe(_ rect: CGRect) -> String {
  String(format: "x %.1f...%.1f  y %.1f...%.1f", rect.minX, rect.maxX, rect.minY, rect.maxY)
}

@MainActor
func run() {
  let pixelWidth = 640
  let pixelHeight = 420
  let wrapWide: CGFloat = 560
  let wrapNarrow: CGFloat = 200
  let source = makeSource(width: pixelWidth, height: pixelHeight)
  let reference = SourceImageReference(
    identifier: "annotation-text-flow",
    pixelWidth: source.width,
    pixelHeight: source.height
  )

  let wideLayout = AnnotationTextLayout.layout(text: bodyText, fontSize: fontSize, width: wrapWide)
  let narrowLayout = AnnotationTextLayout.layout(text: bodyText, fontSize: fontSize, width: wrapNarrow)
  check(
    narrowLayout.lines > wideLayout.lines,
    "wrapping: narrower box takes more lines at the same font size",
    "\(wideLayout.lines) lines at \(Int(wrapWide))pt vs \(narrowLayout.lines) lines at \(Int(wrapNarrow))pt, font \(fontSize)pt"
  )
  check(
    narrowLayout.height > wideLayout.height,
    "wrapping: narrower box is taller",
    String(
      format: "%.1fpt tall at %dpt wide vs %.1fpt tall at %dpt wide",
      narrowLayout.height,
      Int(wrapNarrow),
      wideLayout.height,
      Int(wrapWide)
    )
  )
  let narrowBox = AnnotationTextLayout.boxSize(text: bodyText, fontSize: fontSize, width: wrapNarrow)
  check(
    narrowBox.width <= wrapNarrow,
    "wrapping: the wrapped box holds the narrower width",
    String(format: "box %.1fpt wide, limit %.1fpt", narrowBox.width, wrapNarrow)
  )

  let model = AnnotationEditorModel(image: source, reference: reference)
  model.fontSize = fontSize
  let canvas = AnnotationCanvasView(model: model)
  canvas.frame = CGRect(x: 0, y: 0, width: pixelWidth + 32, height: pixelHeight + 32)

  var item = AnnotationItem(kind: .text, style: model.makeStyle(for: .text), start: CGPoint(x: 30, y: 30))
  item.style.text = bodyText
  let wideBox = AnnotationTextLayout.boxSize(text: bodyText, fontSize: fontSize, width: wrapWide)
  item.end = CGPoint(x: 30 + wideBox.width, y: 30 + wideBox.height)
  model.commit { $0.append(item) }

  let wideInk = textInk(document: model.document, image: source)
  if let ink = wideInk {
    check(
      ink.maxX <= item.bounds.maxX + 1 && ink.maxY <= item.bounds.maxY + 1,
      "render: the wide box contains its ink",
      "ink \(describe(CGRect(x: ink.minX, y: ink.minY, width: ink.maxX - ink.minX, height: ink.maxY - ink.minY))) in box \(describe(item.bounds))"
    )
  } else {
    check(false, "render: the wide box contains its ink", "no ink found")
  }

  canvas.updateResize(
    id: item.id,
    original: item,
    originalRect: item.bounds.standardized,
    handle: .right,
    to: CGPoint(x: item.start.x + wrapNarrow, y: item.start.y + wideBox.height)
  )
  guard let resized = model.document.item(id: item.id) else {
    check(false, "resize: the item survives the drag", "missing item after updateResize")
    print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) CHECK(S) FAILED")
    exit(failures == 0 ? 0 : 1)
  }

  let resizedLayout = AnnotationTextLayout.layout(
    text: resized.style.text,
    fontSize: resized.style.fontSize,
    width: resized.bounds.width
  )
  check(
    resized.bounds.width <= wrapNarrow + 0.5,
    "resize: the box takes the dragged width",
    String(format: "width %.1fpt from a drag to %.1fpt", resized.bounds.width, wrapNarrow)
  )
  check(
    resizedLayout.lines > wideLayout.lines,
    "resize: the committed item re-wraps into more lines",
    "\(resizedLayout.lines) lines after resize vs \(wideLayout.lines) before"
  )
  check(
    resized.bounds.height > item.bounds.height,
    "resize: the box grows vertically for the re-flowed text",
    String(format: "height %.1fpt after vs %.1fpt before", resized.bounds.height, item.bounds.height)
  )
  check(
    resized.style.fontSize == item.style.fontSize,
    "resize: the font size is unchanged",
    "fontSize \(resized.style.fontSize)pt before and after"
  )

  if let ink = textInk(document: model.document, image: source) {
    check(
      ink.maxX <= resized.bounds.maxX + 1,
      "resize: the re-flowed text renders inside the new width",
      "ink right edge \(String(format: "%.1f", ink.maxX)) vs box right edge \(String(format: "%.1f", resized.bounds.maxX))"
    )
    check(
      ink.maxY <= resized.bounds.maxY + 1,
      "resize: the re-flowed text renders inside the box height",
      "ink bottom \(String(format: "%.1f", ink.maxY)) vs box bottom \(String(format: "%.1f", resized.bounds.maxY))"
    )
  } else {
    check(false, "resize: the re-flowed text renders inside the new width", "no ink found")
  }

  let editModel = AnnotationEditorModel(image: source, reference: reference)
  editModel.fontSize = fontSize
  let editCanvas = AnnotationCanvasView(model: editModel)
  editCanvas.frame = CGRect(x: 0, y: 0, width: pixelWidth + 32, height: pixelHeight + 32)
  let scale = editCanvas.currentLayout().scale
  editCanvas.beginTextEditing(at: CGPoint(x: 40, y: 60))
  let idleHeight = editCanvas.textEditor.frame.height
  editCanvas.textEditor.string = bodyText
  editCanvas.layoutTextEditor()

  let editorFrame = editCanvas.textEditor.frame
  let padding = AnnotationPresets.defaultTextEditorPadding
  let editorPointSize = AnnotationCanvasView.textEditorPointSize(fontSize, scale: scale)
  let usedHeight: CGFloat
  if let layoutManager = editCanvas.textEditor.layoutManager,
    let container = editCanvas.textEditor.textContainer
  {
    layoutManager.ensureLayout(for: container)
    usedHeight = layoutManager.usedRect(for: container).height
  } else {
    usedHeight = 0
  }
  check(
    editorFrame.height + 2 >= usedHeight + padding * 2,
    "editing: the field is tall enough for every laid-out line",
    String(format: "field %.1fpt tall, laid-out text %.1fpt plus %.0fpt padding", editorFrame.height, usedHeight, padding * 2)
  )
  check(
    editorFrame.height > idleHeight + 1,
    "editing: the field grows once the text wraps past one line",
    String(format: "%.1fpt empty vs %.1fpt typed", idleHeight, editorFrame.height)
  )
  check(
    usedHeight >= AnnotationTextLayout.lineHeight(fontSize: editorPointSize) * 2,
    "editing: the typed text wraps onto more than one line",
    String(
      format: "%.1fpt of lines at %.1fpt per line, field %.0fpt wide",
      usedHeight,
      AnnotationTextLayout.lineHeight(fontSize: editorPointSize),
      editorFrame.width
    )
  )

  editCanvas.endTextEditing(commit: true)
  if let committed = editModel.document.items.last {
    let expectedWidth = (AnnotationPresets.defaultTextEditorWidth - padding * 2) / scale
    let committedLayout = AnnotationTextLayout.layout(
      text: committed.style.text,
      fontSize: committed.style.fontSize,
      width: committed.bounds.width
    )
    check(
      abs(committed.bounds.width - expectedWidth) <= 0.5,
      "editing: the committed box keeps the field's wrap width",
      String(format: "committed %.1fpt wide, field text area %.1fpt", committed.bounds.width, expectedWidth)
    )
    check(
      committedLayout.lines >= 2,
      "editing: the committed item keeps the wrapped lines",
      "\(committedLayout.lines) lines, box \(describe(committed.bounds))"
    )
    check(
      committed.bounds.height + 1 >= committedLayout.height,
      "editing: the committed box is as tall as the laid-out text",
      String(format: "box %.1fpt tall, laid-out text %.1fpt tall", committed.bounds.height, committedLayout.height)
    )
    if let ink = textInk(document: editModel.document, image: source) {
      check(
        ink.maxX <= committed.bounds.maxX + 1 && ink.maxY <= committed.bounds.maxY + 1,
        "editing: what was typed renders fully inside the committed box",
        "ink \(describe(CGRect(x: ink.minX, y: ink.minY, width: ink.maxX - ink.minX, height: ink.maxY - ink.minY))) in box \(describe(committed.bounds))"
      )
    } else {
      check(false, "editing: what was typed renders fully inside the committed box", "no ink found")
    }
  } else {
    check(false, "editing: the typed text commits as one item", "no committed item")
  }

  print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) CHECK(S) FAILED")
  exit(failures == 0 ? 0 : 1)
}

await run()
