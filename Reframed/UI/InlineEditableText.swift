import AppKit
import SwiftUI

struct InlineEditableText: View {
  let text: String
  let onCommit: (String) -> Void

  @State private var isEditing = false
  @State private var editText = ""
  @State private var eventMonitor: Any?
  @State private var fieldFrame: CGRect = .zero
  @State private var fieldWindow: NSWindow?
  @FocusState private var isFocused: Bool
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let _ = colorScheme
    if isEditing {
      TextField("", text: $editText)
        .font(.system(size: FontSize.xs))
        .foregroundStyle(ReframedColors.primaryText)
        .textFieldStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FieldFrameReader(onChange: updateFieldGeometry).frame(maxWidth: .infinity, maxHeight: .infinity))
        .background(ReframedColors.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(ReframedColors.border))
        .focused($isFocused)
        .onSubmit { commit() }
        .onChange(of: isFocused) { _, focused in
          if !focused { commit() }
        }
        .onExitCommand { cancel() }
        .onAppear { isFocused = true }
        .onDisappear { stopMonitor() }
    } else {
      HStack(spacing: 4) {
        Text(text)
          .font(.system(size: FontSize.xs))
          .foregroundStyle(ReframedColors.primaryText)
          .lineLimit(1)

        Spacer()

        Image(systemName: "pencil")
          .font(.system(size: FontSize.xs))
          .foregroundStyle(ReframedColors.secondaryText)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(ReframedColors.fieldBackground.opacity(0.5))
      .clipShape(RoundedRectangle(cornerRadius: Radius.md))
      .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(ReframedColors.border))
      .onTapGesture { startEditing() }
      .onDisappear { stopMonitor() }
    }
  }

  private func updateFieldGeometry(frame: CGRect, window: NSWindow?) {
    fieldFrame = frame
    fieldWindow = window
  }

  private func startMonitor() {
    guard eventMonitor == nil else { return }
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
      MainActor.assumeIsolated {
        let isInside = event.window === fieldWindow && fieldFrame.contains(event.locationInWindow)
        if !isInside {
          commit()
          isFocused = false
        }
      }
      return event
    }
  }

  private func stopMonitor() {
    if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    eventMonitor = nil
  }

  private func startEditing() {
    editText = text
    isEditing = true
    startMonitor()
  }

  private func commit() {
    guard isEditing else { return }
    let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, trimmed != text {
      onCommit(trimmed)
    }
    isEditing = false
    stopMonitor()
  }

  private func cancel() {
    guard isEditing else { return }
    isEditing = false
    stopMonitor()
  }
}

private struct FieldFrameReader: NSViewRepresentable {
  let onChange: (CGRect, NSWindow?) -> Void

  func makeNSView(context: Context) -> ReportingView {
    let view = ReportingView()
    view.onChange = onChange
    return view
  }

  func updateNSView(_ view: ReportingView, context: Context) {
    view.onChange = onChange
    view.report()
  }

  final class ReportingView: NSView {
    var onChange: ((CGRect, NSWindow?) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }

    override func layout() {
      super.layout()
      report()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      report()
    }

    func report() {
      onChange?(convert(bounds, to: nil), window)
    }
  }
}
