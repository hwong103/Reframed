import SwiftUI

@MainActor
struct CaptureAnnotationToolbarActions {
  let undo: () -> Void
  let redo: () -> Void
  let deleteSelected: () -> Void
  let copy: () -> Void
  let save: () -> Void
  let saveAndCopy: () -> Void
  let captureText: () -> Void
  let beautify: () -> Void
  let pin: () -> Void
  let openInWindow: () -> Void
  let openInPreview: () -> Void
  let scrollingCapture: () -> Void
  let makeDragItem: () -> NSPasteboardItem?
  let cancel: () -> Void
  let selectTool: (CaptureAnnotationTool) -> Void
  let applyStyle: () -> Void
}

@MainActor
struct CaptureAnnotationToolbarView: View {
  @Bindable var state: CaptureAnnotationState
  let actions: CaptureAnnotationToolbarActions
  @State private var showsColor = false

  var body: some View {
    HStack(spacing: 5) {
      tools
      divider
      colorControl
      actionsRow
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(CaptureAnnotationChrome.surface, in: RoundedRectangle(cornerRadius: Radius.xl))
    .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(CaptureAnnotationChrome.divider))
    .shadow(color: CaptureAnnotationChrome.shadow, radius: 8, y: 2)
    .fixedSize()
    .environment(\.colorScheme, .light)
    .captureArrowCursor()
    .onChange(of: state.opacity) { actions.applyStyle() }
    .onChange(of: state.thickness) { actions.applyStyle() }
    .onChange(of: state.size) { actions.applyStyle() }
    .onChange(of: state.redaction) { actions.applyStyle() }
  }

  private var divider: some View {
    Rectangle()
      .fill(CaptureAnnotationChrome.divider)
      .frame(width: 1, height: 26)
  }

  private var tools: some View {
    HStack(spacing: 3) {
      ForEach(CaptureAnnotationTool.allCases, id: \.self) { tool in
        IconButton(systemImage: tool.systemImage, isSelected: state.tool == tool, help: tool.tooltip) {
          actions.selectTool(tool)
        }
      }
    }
  }

  private var colorControl: some View {
    Button {
      showsColor.toggle()
    } label: {
      Circle()
        .fill(Color(cgColor: state.selectedColor.cgColor))
        .frame(width: 22, height: 22)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.35)))
        .frame(width: 32, height: 32)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
    .buttonStyle(PlainCustomButtonStyle())
    .help("Colour, opacity and thickness")
    .popover(isPresented: $showsColor, arrowEdge: .bottom) {
      AnnotationColorPopover(
        state: state,
        onStyleChange: { actions.applyStyle() },
        onSetDefault: { state.setAsDefaultStyle() }
      )
    }
    .captureArrowCursor()
  }

  private var actionsRow: some View {
    HStack(spacing: 3) {
      IconButton(
        systemImage: "arrow.uturn.backward",
        isDimmed: !state.canUndo,
        help: "Undo (Command-Z)"
      ) {
        actions.undo()
      }
      .disabled(!state.canUndo)
      IconButton(
        systemImage: "xmark",
        tint: CaptureAnnotationChrome.delete,
        isDimmed: !state.hasSelection,
        help: "Delete annotation"
      ) {
        actions.deleteSelected()
      }
      .disabled(!state.hasSelection)
      IconButton(systemImage: "pin", help: "Pin (T)") { actions.pin() }
      IconButton(
        systemImage: "sparkles",
        isSelected: state.beautifyEnabled,
        help: "Beautify (B)"
      ) {
        actions.beautify()
      }
      IconButton(systemImage: "macwindow", help: "Open in Window (W)") { actions.openInWindow() }
      IconButton(systemImage: "eye", help: "Open in Preview (P)") { actions.openInPreview() }
      IconButton(systemImage: "text.viewfinder", help: "Capture Text (O)") { actions.captureText() }
      IconButton(systemImage: "square.and.arrow.down", help: "Save (Command-S)") { actions.save() }
      IconButton(systemImage: "doc.on.doc", help: "Copy to Clipboard (Return)") { actions.copy() }
      CaptureAnnotationDragSource(makeItem: actions.makeDragItem, copy: actions.copy)
        .frame(width: 32, height: 32)
        .captureArrowCursor()
      IconButton(
        systemImage: "arrow.up.and.down.text.horizontal",
        help: "Scrolling capture (S)"
      ) {
        actions.scrollingCapture()
      }
    }
  }
}
