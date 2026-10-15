import AppKit
import CoreGraphics
import CoreText
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

func laidOutLineRects(_ item: AnnotationItem) -> [CGRect] {
  guard let color = CGColor(colorSpace: AnnotationRenderer.colorSpace, components: [0, 0, 0, 1]) else {
    return []
  }
  let attributed = AnnotationTextLayout.attributedText(
    item.style.text,
    fontSize: item.style.fontSize,
    color: color
  )
  let framesetter = CTFramesetterCreateWithAttributedString(attributed)
  let size = CGSize(width: item.bounds.width, height: item.bounds.height)
  let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
  let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
  let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
  var origins = [CGPoint](repeating: .zero, count: lines.count)
  CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
  return zip(lines, origins).map { line, origin in
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    return CGRect(
      x: origin.x + ink.minX,
      y: origin.y + ink.minY,
      width: ink.width,
      height: ink.height
    )
  }
}

func laidOutLineCount(_ text: String, _ fontSize: CGFloat, _ width: CGFloat) -> Int {
  AnnotationTextLayout.layout(text: text, fontSize: fontSize, width: width).lines
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
  let resizedRects = laidOutLineRects(resized)
  let resizedExpected = laidOutLineCount(resized.style.text, resized.style.fontSize, resized.bounds.width)
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
  check(
    resizedRects.count == resizedExpected,
    "resize: the frame lays out every wrapped line, none dropped",
    "\(resizedRects.count) lines drawn, \(resizedExpected) laid out, last line ink bottom \(String(format: "%.1f", resizedRects.map(\.minY).min() ?? 0)) in a \(String(format: "%.1f", resized.bounds.height))pt box"
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

  let dragModel = AnnotationEditorModel(image: source, reference: reference)
  dragModel.fontSize = fontSize
  let dragCanvas = AnnotationCanvasView(model: dragModel)
  dragCanvas.frame = CGRect(x: 0, y: 0, width: pixelWidth + 32, height: pixelHeight + 32)
  var dragItem = AnnotationItem(kind: .text, style: dragModel.makeStyle(for: .text), start: CGPoint(x: 30, y: 30))
  dragItem.style.text = bodyText
  dragItem.end = CGPoint(x: 30 + narrowBox.width, y: 30 + narrowBox.height)
  dragModel.commit { $0.append(dragItem) }
  let beforeDrag = dragItem.bounds
  dragCanvas.updateResize(
    id: dragItem.id,
    original: dragItem,
    originalRect: beforeDrag,
    handle: .bottom,
    to: CGPoint(x: beforeDrag.midX, y: beforeDrag.maxY + 30)
  )
  let slackened = dragModel.document.item(id: dragItem.id) ?? dragItem
  check(
    abs(slackened.bounds.height - (beforeDrag.height + 30)) <= 0.5 && abs(slackened.bounds.minY - beforeDrag.minY) <= 0.5,
    "drag: the bottom handle adds slack below the text",
    String(
      format: "height %.1f to %.1f, top %.1f to %.1f",
      beforeDrag.height,
      slackened.bounds.height,
      beforeDrag.minY,
      slackened.bounds.minY
    )
  )
  dragCanvas.updateResize(
    id: dragItem.id,
    original: slackened,
    originalRect: slackened.bounds.standardized,
    handle: .top,
    to: CGPoint(x: slackened.bounds.midX, y: slackened.bounds.minY - 25)
  )
  let raised = dragModel.document.item(id: dragItem.id) ?? slackened
  check(
    abs(raised.bounds.maxY - slackened.bounds.maxY) <= 0.5 && abs(raised.bounds.height - (slackened.bounds.height + 25)) <= 0.5,
    "drag: the top handle keeps the bottom edge anchored",
    String(
      format: "bottom %.1f to %.1f, height %.1f to %.1f",
      slackened.bounds.maxY,
      raised.bounds.maxY,
      slackened.bounds.height,
      raised.bounds.height
    )
  )
  dragCanvas.updateResize(
    id: dragItem.id,
    original: raised,
    originalRect: raised.bounds.standardized,
    handle: .top,
    to: CGPoint(x: raised.bounds.midX, y: raised.bounds.maxY - 4)
  )
  let squashed = dragModel.document.item(id: dragItem.id) ?? raised
  check(
    squashed.bounds.height + 0.5
      >= AnnotationTextLayout.boxSize(
        text: squashed.style.text,
        fontSize: squashed.style.fontSize,
        width: squashed.bounds.width
      ).height,
    "drag: a crushed top handle still holds every line",
    String(
      format: "height %.1f, laid-out text %.1f, bottom %.1f",
      squashed.bounds.height,
      AnnotationTextLayout.boxSize(
        text: squashed.style.text,
        fontSize: squashed.style.fontSize,
        width: squashed.bounds.width
      ).height,
      squashed.bounds.maxY
    )
  )

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

  let fontModel = AnnotationEditorModel(image: source, reference: reference)
  fontModel.fontSize = fontSize
  let fontCanvas = AnnotationCanvasView(model: fontModel)
  fontCanvas.frame = CGRect(x: 0, y: 0, width: pixelWidth + 32, height: pixelHeight + 32)
  var scaled = AnnotationItem(kind: .text, style: fontModel.makeStyle(for: .text), start: CGPoint(x: 40, y: 40))
  scaled.style.text = bodyText
  scaled.end = CGPoint(x: 40 + wideBox.width, y: 40 + wideBox.height)
  scaled = AnnotationTextLayout.fitted(scaled)
  fontModel.commit { $0.append(scaled) }
  fontModel.select(scaled.id)
  fontModel.setFontSize(fontSize + 18)
  if let grown = fontModel.document.item(id: scaled.id) {
    let grownLines = laidOutLineCount(grown.style.text, grown.style.fontSize, grown.bounds.width)
    let grownRects = laidOutLineRects(grown)
    let inside = grownRects.allSatisfy {
      $0.minX >= -2 && $0.maxX <= grown.bounds.width + 2 && $0.minY >= -2 && $0.maxY <= grown.bounds.height + 2
    }
    check(
      grown.style.text == scaled.style.text,
      "font size: the text is unchanged",
      "\(grown.style.text.count) characters before and after"
    )
    check(
      grown.bounds.height + 0.5
        >= AnnotationTextLayout.boxSize(
          text: grown.style.text,
          fontSize: grown.style.fontSize,
          width: grown.bounds.width
        ).height,
      "font size: the box grows to hold the laid-out text",
      String(
        format: "font %.0fpt to %.0fpt, box %.1fpt tall, laid-out text %.1fpt",
        scaled.style.fontSize,
        grown.style.fontSize,
        grown.bounds.height,
        AnnotationTextLayout.boxSize(
          text: grown.style.text,
          fontSize: grown.style.fontSize,
          width: grown.bounds.width
        ).height
      )
    )
    check(
      grownRects.count == grownLines,
      "font size: every laid-out line is in the frame",
      "\(grownRects.count) lines drawn, \(grownLines) laid out"
    )
    check(
      inside,
      "font size: every line's ink is inside the box",
      "last line ink bottom \(String(format: "%.1f", grownRects.map(\.minY).min() ?? 0)) in a \(String(format: "%.1f", grown.bounds.height))pt box, ink bottom \(String(format: "%.1f", grownRects.map(\.maxY).max() ?? 0)) at the top"
    )
    if let ink = textInk(document: fontModel.document, image: source) {
      check(
        ink.maxX <= grown.bounds.maxX + 1 && ink.maxY <= grown.bounds.maxY + 1,
        "font size: the larger text still renders inside the box",
        "ink bottom \(String(format: "%.1f", ink.maxY)) vs box bottom \(String(format: "%.1f", grown.bounds.maxY))"
      )
    } else {
      check(false, "font size: the larger text still renders inside the box", "no ink found")
    }
  } else {
    check(false, "font size: the item survives the style change", "missing item after setFontSize")
  }

  let tinyModel = AnnotationEditorModel(image: source, reference: reference)
  tinyModel.fontSize = fontSize
  let tinyCanvas = AnnotationCanvasView(model: tinyModel)
  tinyCanvas.frame = CGRect(x: 0, y: 0, width: 192, height: 137)
  let tinyScale = tinyCanvas.currentLayout().scale
  tinyCanvas.beginTextEditing(at: CGPoint(x: 60, y: 70))
  tinyCanvas.textEditor.string = bodyText
  tinyCanvas.layoutTextEditor()
  let tinyPointSize = tinyCanvas.textEditor.font?.pointSize ?? 0
  let tinyVisible = tinyCanvas.visibleCanvasRect()
  let tinyWidth = min(AnnotationPresets.defaultTextEditorWidth, tinyVisible.width)
  let tinyTextWidth = max(tinyWidth - AnnotationPresets.defaultTextEditorPadding * 2, 1)
  var tinyUsed: CGFloat = 0
  if let layoutManager = tinyCanvas.textEditor.layoutManager,
    let container = tinyCanvas.textEditor.textContainer
  {
    layoutManager.ensureLayout(for: container)
    tinyUsed = layoutManager.usedRect(for: container).height
  }
  let tinyShared = AnnotationTextLayout.boxSize(text: bodyText, fontSize: tinyPointSize, width: tinyTextWidth).height
  check(
    abs(tinyScale - 0.25) <= 0.001,
    "small scale: the canvas resolves to 0.25",
    String(format: "scale %.3f on a %dx%d canvas", tinyScale, pixelWidth, pixelHeight)
  )
  check(
    abs(tinyPointSize - fontSize * tinyScale) <= 0.001,
    "small scale: the editor font is the shared font size, no independent floor",
    String(format: "editor %.2fpt, shared layout %.2fpt", tinyPointSize, fontSize * tinyScale)
  )
  check(
    abs(tinyUsed - tinyShared) <= 2,
    "small scale: the editor lays the text out at the shared height",
    String(format: "editor %.1fpt, shared layout %.1fpt", tinyUsed, tinyShared)
  )

  let windowView = NSView(frame: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
  let smallCapture = CGRect(x: 50, y: 40, width: 200, height: 120)
  let container = NSView(frame: smallCapture)
  container.wantsLayer = true
  container.layer?.masksToBounds = true
  windowView.addSubview(container)
  let clipModel = AnnotationEditorModel(image: source, reference: reference)
  clipModel.fontSize = fontSize
  let clipCanvas = AnnotationCanvasView(model: clipModel)
  clipCanvas.frame = CGRect(
    origin: CGPoint(x: -smallCapture.minX, y: -smallCapture.minY),
    size: CGSize(width: pixelWidth, height: pixelHeight)
  )
  container.addSubview(clipCanvas)
  let clipVisible = clipCanvas.visibleCanvasRect()
  let clickView = CGPoint(x: clipVisible.midX - 30, y: clipVisible.midY)
  clipCanvas.beginTextEditing(at: clipCanvas.sourcePoint(clickView))
  clipCanvas.textEditor.string = bodyText
  clipCanvas.layoutTextEditor()
  let scrollFrame = clipCanvas.textScrollView.frame
  var clipUsed: CGFloat = 0
  if let layoutManager = clipCanvas.textEditor.layoutManager,
    let textContainer = clipCanvas.textEditor.textContainer
  {
    layoutManager.ensureLayout(for: textContainer)
    clipUsed = layoutManager.usedRect(for: textContainer).height
  }
  check(
    windowView.bounds.insetBy(dx: -0.5, dy: -0.5).contains(scrollFrame) && clipVisible.contains(clickView),
    "small capture: the editor stays inside the window around a small capture",
    "editor \(describe(scrollFrame)) in window \(describe(windowView.bounds)), capture \(describe(clipVisible))"
  )
  check(
    clipCanvas.textEditor.frame.height + 0.5 >= clipUsed + AnnotationPresets.defaultTextEditorPadding * 2,
    "small capture: the editor document holds every line, none clipped",
    String(
      format: "document %.1fpt, text %.1fpt plus %.0fpt padding",
      clipCanvas.textEditor.frame.height,
      clipUsed,
      AnnotationPresets.defaultTextEditorPadding * 2
    )
  )
  check(
    clipCanvas.textScrollView.hasVerticalScroller,
    "small capture: the editor scrolls when the text outgrows the capture",
    "hasVerticalScroller \(clipCanvas.textScrollView.hasVerticalScroller), editor \(describe(scrollFrame))"
  )

  let overlay = NSView(frame: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
  let capture = CGRect(x: 200, y: 150, width: 200, height: 30)
  let maskedClip = NSView(frame: capture)
  maskedClip.wantsLayer = true
  maskedClip.layer?.masksToBounds = true
  overlay.addSubview(maskedClip)
  let tallModel = AnnotationEditorModel(image: source, reference: reference)
  tallModel.fontSize = fontSize * 2
  let tallCanvas = AnnotationCanvasView(model: tallModel)
  tallCanvas.frame = CGRect(origin: CGPoint(x: -capture.minX, y: -capture.minY), size: overlay.frame.size)
  maskedClip.addSubview(tallCanvas)
  tallCanvas.beginTextEditing(at: tallCanvas.sourcePoint(CGPoint(x: capture.midX, y: capture.midY)))
  tallCanvas.textEditor.string = bodyText
  tallCanvas.layoutTextEditor()
  let tallBox = tallCanvas.textScrollView.frame
  let oneLine =
    AnnotationTextLayout.lineHeight(fontSize: tallModel.fontSize)
    + AnnotationPresets.defaultTextEditorPadding * 2
  check(
    tallBox.height + 0.5 >= oneLine,
    "short capture: the editor viewport holds a full line plus padding",
    String(
      format: "viewport %.1fpt, one line %.1fpt, capture %.1fpt tall",
      tallBox.height,
      oneLine,
      capture.height
    )
  )
  check(
    overlay.bounds.insetBy(dx: -0.5, dy: -0.5).contains(tallBox),
    "short capture: the editor stays inside the window",
    "editor \(describe(tallBox)) in window \(describe(overlay.bounds))"
  )
  check(
    tallBox.maxY > capture.maxY || tallBox.minY < capture.minY,
    "short capture: the editor escapes the capture so the line is readable",
    "editor \(describe(tallBox)) vs capture \(describe(capture))"
  )
  let editorHost = tallCanvas.textScrollView.superview
  check(
    editorHost === overlay,
    "short capture: the editor is hosted outside the masked capture container",
    "host \(editorHost === overlay ? "overlay" : String(describing: editorHost)), masked clip \(describe(maskedClip.frame))"
  )
  let escapeProbe = CGPoint(x: tallBox.midX, y: capture.maxY + 20)
  let resolved = overlay.hitTest(escapeProbe)
  check(
    !capture.contains(escapeProbe)
      && (resolved === tallCanvas.textEditor || (resolved?.isDescendant(of: tallCanvas.textScrollView) ?? false)),
    "short capture: a point in the escaped editor resolves to the editor",
    "point \(describe(CGRect(x: escapeProbe.x, y: escapeProbe.y, width: 1, height: 1))) outside \(describe(capture)) resolved to \(resolved.map { String(describing: type(of: $0)) } ?? "nil")"
  )
  tallCanvas.endTextEditing(commit: true)
  if let committed = tallModel.document.items.last {
    let anchorView = tallCanvas.viewPoint(committed.start)
    check(
      abs(anchorView.x - tallBox.minX) <= 0.6 && abs(anchorView.y - tallBox.maxY) <= 0.6,
      "short capture: the committed text lands where the editor sat",
      String(
        format: "committed corner (%.1f, %.1f) vs editor corner (%.1f, %.1f)",
        anchorView.x,
        anchorView.y,
        tallBox.minX,
        tallBox.maxY
      )
    )
    check(
      committed.style.text == bodyText,
      "short capture: the committed text is whole",
      "\(committed.style.text.count) of \(bodyText.count) characters"
    )
  } else {
    check(false, "short capture: the committed text lands where the editor sat", "no committed item")
  }

  let scrollModel = AnnotationEditorModel(image: source, reference: reference)
  scrollModel.fontSize = fontSize
  let scrollCanvas = AnnotationCanvasView(model: scrollModel)
  scrollCanvas.frame = CGRect(x: 0, y: 0, width: pixelWidth + 32, height: pixelHeight + 32)
  scrollCanvas.beginTextEditing(at: CGPoint(x: 60, y: 200))
  scrollCanvas.textScrollView.scrollerStyle = .legacy
  scrollCanvas.textScrollView.autohidesScrollers = false
  scrollCanvas.textEditor.string = String(repeating: bodyText + " ", count: 40)
  scrollCanvas.layoutTextEditor()
  let outerWidth = scrollCanvas.textScrollView.frame.width
  scrollCanvas.textScrollView.tile()
  let contentWidth = scrollCanvas.textScrollView.contentSize.width
  let scrollerWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
  let documentWidth = scrollCanvas.textEditor.frame.width
  check(
    abs(documentWidth - (outerWidth - scrollerWidth)) <= 1,
    "scroller: the document takes the content width, not the outer width",
    String(
      format: "outer %.1fpt - scroller %.1fpt = %.1fpt, document %.1fpt, tiled content %.1fpt",
      outerWidth,
      scrollerWidth,
      outerWidth - scrollerWidth,
      documentWidth,
      contentWidth
    )
  )
  check(
    contentWidth + 0.5 >= documentWidth,
    "scroller: the document never overlaps the scroller",
    String(format: "tiled content %.1fpt, document %.1fpt", contentWidth, documentWidth)
  )
  check(
    !scrollCanvas.textScrollView.hasHorizontalScroller
      && scrollCanvas.textEditor.frame.width <= scrollCanvas.textScrollView.frame.width,
    "scroller: the editor never scrolls horizontally",
    String(
      format: "horizontal scroller %@, document %.1fpt in a %.1fpt box",
      scrollCanvas.textScrollView.hasHorizontalScroller ? "on" : "off",
      scrollCanvas.textEditor.frame.width,
      scrollCanvas.textScrollView.frame.width
    )
  )

  let hugeText = String(repeating: "The quick brown fox jumps over the lazy dog 0123456789 ", count: 3_200)
  let hugeWidth: CGFloat = 300
  let hugeLayout = AnnotationTextLayout.layout(text: hugeText, fontSize: fontSize, width: hugeWidth)
  let hugeFrame = CTFramesetterCreateFrame(
    CTFramesetterCreateWithAttributedString(AnnotationTextLayout.attributedText(hugeText, fontSize: fontSize)),
    CFRange(location: 0, length: 0),
    CGPath(rect: CGRect(x: 0, y: 0, width: hugeWidth, height: hugeLayout.height), transform: nil),
    nil
  )
  let hugeVisible = CTFrameGetVisibleStringRange(hugeFrame)
  let hugeLines = (CTFrameGetLines(hugeFrame) as? [CTLine] ?? []).count
  check(
    hugeVisible.length >= hugeText.count && hugeLines == hugeLayout.lines,
    "long text: the measured height covers every line with no probe limit",
    "\(hugeText.count) characters, \(hugeLines) lines drawn of \(hugeLayout.lines) laid out, height \(String(format: "%.0f", hugeLayout.height))pt"
  )

  let toolModel = AnnotationEditorModel(image: source, reference: reference)
  toolModel.fontSize = fontSize
  toolModel.setTool(.text)
  let toolCanvas = AnnotationCanvasView(model: toolModel)
  toolCanvas.frame = CGRect(x: 0, y: 0, width: pixelWidth + 32, height: pixelHeight + 32)
  var placed = AnnotationItem(kind: .text, style: toolModel.makeStyle(for: .text), start: CGPoint(x: 60, y: 80))
  placed.style.text = bodyText
  placed.end = CGPoint(x: 60 + narrowBox.width, y: 80 + narrowBox.height)
  toolModel.commit { $0.append(placed) }
  toolModel.select(nil)
  let insideView = toolCanvas.viewPoint(CGPoint(x: placed.bounds.midX, y: placed.bounds.midY))
  let insideSource = toolCanvas.sourcePoint(insideView)
  check(
    toolCanvas.textItem(at: insideSource)?.id == placed.id,
    "text tool: a committed text item is hit-testable inside its box",
    "hit \(toolCanvas.textItem(at: insideSource)?.id.uuidString ?? "nil") vs item \(placed.id.uuidString)"
  )
  toolCanvas.beginInteraction(at: insideView)
  check(
    toolModel.selectedItem?.id == placed.id && toolCanvas.pendingText == nil,
    "text tool: clicking a committed text item selects it instead of opening an editor",
    "selected \(toolModel.selectedItem?.id.uuidString ?? "nil"), editor open \(toolCanvas.pendingText != nil)"
  )
  toolCanvas.continueInteraction(at: CGPoint(x: insideView.x + 40, y: insideView.y + 25))
  let moved = toolModel.document.item(id: placed.id)
  check(
    (moved?.bounds.minX ?? 0) > placed.bounds.minX + 10 && (moved?.bounds.minY ?? 0) < placed.bounds.minY - 10,
    "text tool: dragging a selected text item moves it",
    "box \(describe(placed.bounds)) moved to \(moved.map { describe($0.bounds) } ?? "missing")"
  )
  toolCanvas.finishInteraction()

  if let selected = toolModel.document.item(id: placed.id) {
    let rightHandle = toolCanvas.viewPoint(CGPoint(x: selected.bounds.maxX, y: selected.bounds.midY))
    let handle = toolCanvas.handleHit(at: rightHandle)
    check(
      handle != nil,
      "text tool: the selected text item shows hit-testable handles",
      "handle \(handle.map { String(describing: $0) } ?? "nil") at \(describe(CGRect(x: rightHandle.x, y: rightHandle.y, width: 1, height: 1)))"
    )
    toolCanvas.beginInteraction(at: rightHandle)
    toolCanvas.continueInteraction(
      at: toolCanvas.viewPoint(CGPoint(x: selected.bounds.maxX + 140, y: selected.bounds.midY))
    )
    toolCanvas.finishInteraction()
    let widened = toolModel.document.item(id: placed.id)
    check(
      (widened?.bounds.width ?? 0) > selected.bounds.width + 100,
      "text tool: dragging the handle resizes the text item",
      "width \(selected.bounds.width) to \(widened?.bounds.width ?? 0)"
    )

    toolCanvas.beginTextEditing(existing: selected)
    check(
      toolCanvas.textEditor.string == bodyText,
      "re-edit: the editor opens on the committed text",
      "\(toolCanvas.textEditor.string.count) of \(bodyText.count) characters"
    )
    check(
      toolCanvas.editingTextItem?.id == selected.id && toolCanvas.pendingText != nil,
      "re-edit: the editor targets the existing item",
      "editing \(toolCanvas.editingTextItem?.id.uuidString ?? "nil"), pending \(toolCanvas.pendingText != nil)"
    )
    toolCanvas.textEditor.string = "Short replacement"
    toolCanvas.layoutTextEditor()
    let countBefore = toolModel.document.count
    toolCanvas.endTextEditing(commit: true)
    let edited = toolModel.document.item(id: selected.id)
    check(
      edited?.style.text == "Short replacement" && toolModel.document.count == countBefore,
      "re-edit: committing replaces the item instead of adding one",
      "text \(edited?.style.text ?? "nil"), items \(countBefore) to \(toolModel.document.count)"
    )
    check(
      edited.map { abs($0.bounds.minX - selected.bounds.minX) <= 0.5 && abs($0.bounds.minY - selected.bounds.minY) <= 0.5 } ?? false,
      "re-edit: the item keeps its top-left",
      "was (\(selected.bounds.minX), \(selected.bounds.minY)), now (\(edited?.bounds.minX ?? 0), \(edited?.bounds.minY ?? 0))"
    )
    check(
      edited.map { abs($0.style.fontSize - selected.style.fontSize) <= 0.001 } ?? false,
      "re-edit: the item keeps its font size",
      "fontSize \(selected.style.fontSize) to \(edited?.style.fontSize ?? 0)"
    )
    if let edited {
      let needed = AnnotationTextLayout.boxSize(
        text: edited.style.text,
        fontSize: edited.style.fontSize,
        width: edited.bounds.width
      )
      check(
        edited.bounds.height + 0.5 >= needed.height,
        "re-edit: the committed box still holds the re-laid text",
        String(format: "box %.1fpt tall, laid-out text %.1fpt tall", edited.bounds.height, needed.height)
      )
    }
  } else {
    check(false, "text tool: the selected text item shows hit-testable handles", "item missing after the move")
  }

  toolCanvas.stepStampProvider = { "7" }
  let stampCount = toolModel.document.count
  if let last = toolModel.document.items.last {
    toolCanvas.beginInteraction(
      at: toolCanvas.viewPoint(CGPoint(x: last.bounds.midX, y: last.bounds.midY))
    )
  }
  check(
    toolModel.document.count == stampCount + 1 && toolCanvas.pendingText == nil,
    "step tool: clicking over a text item still stamps a new step",
    "items \(stampCount) to \(toolModel.document.count), editor open \(toolCanvas.pendingText != nil)"
  )
  toolCanvas.stepStampProvider = nil

  let lowModel = AnnotationEditorModel(image: source, reference: reference)
  lowModel.fontSize = fontSize
  lowModel.setTool(.text)
  let lowCanvas = AnnotationCanvasView(model: lowModel)
  lowCanvas.frame = CGRect(x: 0, y: 0, width: pixelWidth + 32, height: pixelHeight + 32)
  var low = AnnotationItem(kind: .text, style: lowModel.makeStyle(for: .text), start: CGPoint(x: 80, y: 330))
  low.style.text = bodyText
  low.end = CGPoint(x: 80 + narrowBox.width, y: 330 + narrowBox.height)
  lowModel.commit { $0.append(low) }
  lowCanvas.beginTextEditing(existing: low)
  lowCanvas.textEditor.string = "Lower half note"
  lowCanvas.layoutTextEditor()
  lowCanvas.endTextEditing(commit: true)
  let lowEdited = lowModel.document.item(id: low.id)
  check(
    lowEdited.map { abs($0.bounds.minX - low.bounds.minX) <= 0.5 && abs($0.bounds.minY - low.bounds.minY) <= 0.5 } ?? false,
    "re-edit: an item in the lower half keeps its top-left",
    "was (\(low.bounds.minX), \(low.bounds.minY)) in a \(pixelHeight)pt tall canvas, now (\(lowEdited?.bounds.minX ?? 0), \(lowEdited?.bounds.minY ?? 0))"
  )

  print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) CHECK(S) FAILED")
  exit(failures == 0 ? 0 : 1)
}

await run()
