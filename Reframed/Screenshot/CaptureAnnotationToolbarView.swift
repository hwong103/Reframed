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
  let pin: () -> Void
  let openInWindow: () -> Void
  let openInPreview: () -> Void
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
    HStack(spacing: 4) {
      tools
      divider
      colorControl
      actionsRow
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 5)
    .background(CaptureAnnotationChrome.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(CaptureAnnotationChrome.divider))
    .shadow(color: CaptureAnnotationChrome.shadow, radius: 6, y: 2)
    .fixedSize()
    .environment(\.colorScheme, .light)
    .onChange(of: state.opacity) { actions.applyStyle() }
    .onChange(of: state.thickness) { actions.applyStyle() }
    .onChange(of: state.size) { actions.applyStyle() }
  }

  private var divider: some View {
    Rectangle()
      .fill(CaptureAnnotationChrome.divider)
      .frame(width: 1, height: 20)
  }

  private var tools: some View {
    HStack(spacing: 2) {
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
        .frame(width: 18, height: 18)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.35)))
        .frame(width: 26, height: 26)
        .contentShape(RoundedRectangle(cornerRadius: Radius.md))
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
  }

  private var actionsRow: some View {
    HStack(spacing: 2) {
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
      IconButton(systemImage: "macwindow", help: "Open in Window (W)") { actions.openInWindow() }
      IconButton(systemImage: "eye", help: "Open in Preview (P)") { actions.openInPreview() }
      IconButton(systemImage: "text.viewfinder", help: "Capture Text (O)") { actions.captureText() }
      IconButton(systemImage: "square.and.arrow.down", help: "Save (Command-S)") { actions.save() }
      IconButton(systemImage: "doc.on.doc", help: "Copy to Clipboard (Return)") { actions.copy() }
      IconButton(
        systemImage: "arrow.up.and.down.text.horizontal",
        isDimmed: true,
        help: "Scrolling capture is not available yet (S)"
      ) {}
    }
  }
}
