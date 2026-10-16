import CoreGraphics
import Foundation

extension AnnotationCanvasView {
  func dragCompositeImage() -> CGImage? {
    guard isDragging, model.document.hasEffects, let id = draggingItemID else { return nil }
    guard let session = dragSession(for: id) else { return nil }
    return composeDragFrame(session, id: id)
  }

  func clearDragComposition() {
    dragComposition = nil
  }

  private func dragSession(for id: UUID) -> DragComposition? {
    let document = model.document
    guard let index = document.index(of: id), document.items[index].kind != .crop else { return nil }
    let others = document.items.filter { $0.id != id }
    if let session = dragComposition,
      session.itemID == id,
      session.index == index,
      session.others == others,
      session.crop == document.cropRect
    {
      return session
    }
    let session = makeDragSession(document: document, id: id, index: index, others: others)
    dragComposition = session
    return session
  }

  private func makeDragSession(
    document: AnnotationDocument,
    id: UUID,
    index: Int,
    others: [AnnotationItem]
  ) -> DragComposition? {
    let size = AnnotationRenderer.outputSize(for: document)
    let width = Int(size.width)
    let height = Int(size.height)
    guard width > 0, height > 0 else { return nil }
    let prefixDocument = AnnotationDocument(
      source: document.source,
      pixelSize: document.pixelSize,
      items: Array(document.items[..<index]),
      cropRect: document.cropRect
    )
    var prefix = [UInt8](repeating: 0, count: width * height * 4)
    var rendered = false
    prefix.withUnsafeMutableBytes { raw in
      guard let context = AnnotationRenderer.bitmapContext(raw.baseAddress, width: width, height: height) else {
        return
      }
      AnnotationRenderer.renderDirect(prefixDocument, image: model.image, into: context)
      rendered = true
    }
    guard rendered else { return nil }
    return DragComposition(
      itemID: id,
      index: index,
      others: others,
      crop: document.cropRect,
      prefix: prefix,
      suffix: Array(document.items[(index + 1)...]),
      width: width,
      height: height
    )
  }

  private func composeDragFrame(_ session: DragComposition, id: UUID) -> CGImage? {
    let document = model.document
    guard let item = document.item(id: id) else { return nil }
    let viewport = AnnotationRenderer.viewport(for: document)
    var working = session.prefix
    var result: CGImage?
    working.withUnsafeMutableBytes { raw in
      guard let context = AnnotationRenderer.bitmapContext(raw.baseAddress, width: session.width, height: session.height) else {
        return
      }
      AnnotationRenderer.draw(item, in: context, viewport: viewport, document: document)
      for suffixItem in session.suffix {
        AnnotationRenderer.draw(suffixItem, in: context, viewport: viewport, document: document)
      }
      result = context.makeImage()
    }
    return result
  }
}
