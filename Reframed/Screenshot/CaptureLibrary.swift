import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

enum CaptureLibraryFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case screenshots = "Screenshots"
  case recordings = "Recordings"

  var id: Self { self }

  var icon: String {
    switch self {
    case .all: "square.grid.2x2"
    case .screenshots: "photo"
    case .recordings: "video"
    }
  }
}

enum CaptureLibraryKind: String {
  case screenshot
  case recording

  var label: String {
    switch self {
    case .screenshot: "Screenshot"
    case .recording: "Recording"
    }
  }

  var icon: String {
    switch self {
    case .screenshot: "photo"
    case .recording: "video"
    }
  }
}

struct CaptureLibraryItem: Identifiable {
  let id: String
  let kind: CaptureLibraryKind
  let title: String
  let fileURL: URL
  let createdAt: Date
  let width: Int?
  let height: Int?
  let captureMode: CaptureMode?
  let recentCapture: RecentCaptureData?

  var detail: String {
    switch kind {
    case .screenshot:
      if let width, let height {
        return "\(width) x \(height) px"
      }
      return "Screenshot"
    case .recording:
      return captureMode?.libraryLabel ?? "Recording"
    }
  }
}

extension CaptureMode {
  fileprivate var libraryLabel: String {
    switch self {
    case .none: "Recording"
    case .entireScreen: "Display recording"
    case .selectedWindow: "Window recording"
    case .selectedArea: "Area recording"
    case .device: "Device recording"
    }
  }
}

@MainActor
@Observable
final class CaptureLibraryStore {
  var items: [CaptureLibraryItem] = []
  var query = ""
  var filter: CaptureLibraryFilter = .all

  private let session: SessionState
  private let recentCaptures: RecentCaptureStore

  init(session: SessionState, recentCaptures: RecentCaptureStore = .shared) {
    self.session = session
    self.recentCaptures = recentCaptures
  }

  var visibleItems: [CaptureLibraryItem] {
    let terms =
      query
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)

    return items.filter { item in
      let matchesFilter: Bool
      switch filter {
      case .all: matchesFilter = true
      case .screenshots: matchesFilter = item.kind == .screenshot
      case .recordings: matchesFilter = item.kind == .recording
      }
      guard matchesFilter, !terms.isEmpty else { return matchesFilter }

      let haystack = "\(item.title) \(item.fileURL.path) \(item.detail)"
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      return terms.allSatisfy(haystack.contains)
    }
  }

  var screenshotCount: Int { items.filter { $0.kind == .screenshot }.count }
  var recordingCount: Int { items.filter { $0.kind == .recording }.count }

  func refresh() {
    var next: [CaptureLibraryItem] = []

    for capture in recentCaptures.captures {
      let url = recentCaptures.fileURL(for: capture.id)
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      next.append(
        CaptureLibraryItem(
          id: "screenshot:\(capture.id)",
          kind: .screenshot,
          title: capture.filename,
          fileURL: url,
          createdAt: capture.date,
          width: capture.width,
          height: capture.height,
          captureMode: nil,
          recentCapture: capture
        )
      )
    }

    let directory = FileManager.default.projectSaveDirectory()
    let projectURLs =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    for url in projectURLs where url.pathExtension.lowercased() == "frm" {
      guard let project = try? ReframedProject.open(at: url) else { continue }
      next.append(
        CaptureLibraryItem(
          id: projectID(for: url),
          kind: .recording,
          title: project.name,
          fileURL: url,
          createdAt: project.metadata.createdAt,
          width: Int(project.metadata.screenSize.width),
          height: Int(project.metadata.screenSize.height),
          captureMode: project.metadata.captureMode,
          recentCapture: nil
        )
      )
    }

    items = next.sorted { $0.createdAt > $1.createdAt }
  }

  func open(_ item: CaptureLibraryItem) {
    switch item.kind {
    case .screenshot:
      guard let capture = item.recentCapture, let image = recentCaptures.image(for: capture) else {
        presentError("That screenshot is no longer available.")
        return
      }
      let reference = SourceImageReference(
        identifier: item.id,
        pixelWidth: image.width,
        pixelHeight: image.height
      )
      AnnotationEditorWindowController.present(image: image, reference: reference)
    case .recording:
      session.openProject(at: item.fileURL)
    }
  }

  @discardableResult
  func copy(_ item: CaptureLibraryItem) -> Bool {
    guard let capture = item.recentCapture else { return false }
    return recentCaptures.copyToClipboard(capture)
  }

  @discardableResult
  func save(_ item: CaptureLibraryItem) -> URL? {
    guard let capture = item.recentCapture else { return nil }
    return recentCaptures.save(capture)
  }

  func reveal(_ item: CaptureLibraryItem) {
    NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
  }

  @discardableResult
  func rename(_ item: CaptureLibraryItem, to newName: String) -> Bool {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    switch item.kind {
    case .screenshot:
      guard let capture = item.recentCapture else { return false }
      let renamed = recentCaptures.rename(capture, to: trimmed)
      if renamed { refresh() }
      return renamed
    case .recording:
      do {
        var project = try ReframedProject.open(at: item.fileURL)
        try project.rename(to: trimmed)
        refresh()
        return true
      } catch {
        presentError("Could not rename project: \(error.localizedDescription)")
        return false
      }
    }
  }

  @discardableResult
  func confirmDelete(_ item: CaptureLibraryItem) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Move \(item.kind.label.lowercased()) to Trash?"
    alert.informativeText = item.title
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Move to Trash")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return false }
    return delete(item)
  }

  static func projectID(for url: URL) -> String {
    "project:\(url.standardizedFileURL.path)"
  }

  private func delete(_ item: CaptureLibraryItem) -> Bool {
    switch item.kind {
    case .screenshot:
      guard let capture = item.recentCapture else { return false }
      guard recentCaptures.remove(capture) else {
        presentError("Could not move item to Trash.")
        return false
      }
    case .recording:
      do {
        let project = try ReframedProject.open(at: item.fileURL)
        try project.delete()
      } catch {
        presentError("Could not move item to Trash: \(error.localizedDescription)")
        return false
      }
    }
    refresh()
    return true
  }

  private func presentError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Capture Library"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func projectID(for url: URL) -> String {
    Self.projectID(for: url)
  }
}

@MainActor
final class CaptureLibraryWindowController: NSObject, NSWindowDelegate {
  private let session: SessionState
  private var window: NSWindow?
  private lazy var store = CaptureLibraryStore(session: session)

  init(session: SessionState) {
    self.session = session
  }

  func show() {
    store.refresh()
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let view = CaptureLibraryView(store: store)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Capture Library"
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.backgroundColor = ReframedColors.backgroundContainerNS
    window.contentMinSize = NSSize(width: 900, height: 600)
    window.contentView = NSHostingView(rootView: view)
    window.delegate = self
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
  }
}

private struct CaptureLibraryView: View {
  @Bindable var store: CaptureLibraryStore
  @State private var selectionID: String?
  @State private var mcpEnabled = ConfigService.shared.localMCPEnabled
  @State private var copiedEndpoint = false

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Rectangle().fill(ReframedColors.divider).frame(width: 1)
      content
      Rectangle().fill(ReframedColors.divider).frame(width: 1)
      InspectorView(
        item: selectedItem,
        store: store,
        onRename: promptRename,
        onDelete: deleteSelected
      )
      .frame(width: 250)
    }
    .background(ReframedColors.backgroundContainer)
    .frame(minWidth: 900, minHeight: 600)
    .task { store.refresh() }
  }

  private var selectedItem: CaptureLibraryItem? {
    guard let selectionID else { return nil }
    return store.items.first { $0.id == selectionID }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Capture Library")
          .font(.system(size: FontSize.xl, weight: .semibold))
          .foregroundStyle(ReframedColors.primaryText)
        Text("\(store.items.count) local captures")
          .font(.system(size: FontSize.xxs, weight: .medium))
          .foregroundStyle(ReframedColors.secondaryText)
      }
      .padding(.horizontal, 16)
      .padding(.top, 18)
      .padding(.bottom, 14)

      ForEach(CaptureLibraryFilter.allCases) { filter in
        filterButton(filter)
      }

      Spacer(minLength: 20)
      agentSection
      refreshButton
    }
    .frame(width: 210)
    .background(ReframedColors.backgroundPopover)
  }

  private func filterButton(_ filter: CaptureLibraryFilter) -> some View {
    let count: Int
    switch filter {
    case .all: count = store.items.count
    case .screenshots: count = store.screenshotCount
    case .recordings: count = store.recordingCount
    }

    return Button {
      store.filter = filter
      if let item = selectedItem {
        let visible =
          switch filter {
          case .all: true
          case .screenshots: item.kind == .screenshot
          case .recordings: item.kind == .recording
          }
        if !visible { selectionID = nil }
      }
    } label: {
      HStack(spacing: 9) {
        Image(systemName: filter.icon)
          .frame(width: 18)
        Text(filter.rawValue)
        Spacer()
        Text("\(count)")
          .foregroundStyle(ReframedColors.tertiaryText)
      }
      .font(.system(size: FontSize.xs, weight: .medium))
      .foregroundStyle(ReframedColors.primaryText)
      .padding(.horizontal, 12)
      .frame(height: 34)
      .background(
        store.filter == filter ? ReframedColors.selectedBackground : Color.clear,
        in: RoundedRectangle(cornerRadius: Radius.md)
      )
      .padding(.horizontal, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var agentSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("LOCAL AGENT")
          .font(.system(size: FontSize.xxs, weight: .semibold))
          .foregroundStyle(ReframedColors.secondaryText)
        Spacer()
        Toggle("", isOn: $mcpEnabled)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.mini)
          .onChange(of: mcpEnabled) { _, enabled in
            LocalMCPService.shared.setEnabled(enabled)
          }
      }

      Text(mcpEnabled ? "MCP is running on this Mac." : "MCP is off.")
        .font(.system(size: FontSize.xxs))
        .foregroundStyle(ReframedColors.secondaryText)

      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(LocalMCPService.shared.clientConfiguration, forType: .string)
        copiedEndpoint = true
        Task {
          try? await Task.sleep(for: .seconds(1.5))
          copiedEndpoint = false
        }
      } label: {
        Label(
          copiedEndpoint ? "Copied" : "Copy setup",
          systemImage: copiedEndpoint ? "check" : "doc.on.doc"
        )
        .font(.system(size: FontSize.xxs, weight: .medium))
        .frame(maxWidth: .infinity)
        .frame(height: 28)
      }
      .buttonStyle(OutlineButtonStyle())
      .disabled(!mcpEnabled)
    }
    .padding(12)
    .overlay(alignment: .top) {
      Rectangle().fill(ReframedColors.divider).frame(height: 1)
    }
  }

  private var refreshButton: some View {
    Button {
      store.refresh()
    } label: {
      Label("Refresh", systemImage: "arrow.clockwise")
        .font(.system(size: FontSize.xxs, weight: .medium))
        .frame(maxWidth: .infinity)
        .frame(height: 34)
    }
    .buttonStyle(.plain)
    .foregroundStyle(ReframedColors.secondaryText)
    .padding(8)
  }

  private var content: some View {
    VStack(spacing: 0) {
      searchBar
      Rectangle().fill(ReframedColors.divider).frame(height: 1)

      if store.visibleItems.isEmpty {
        ContentUnavailableView(
          store.query.isEmpty ? "No captures yet" : "No matches",
          systemImage: store.query.isEmpty ? "rectangle.on.rectangle" : "magnifyingglass",
          description: Text(
            store.query.isEmpty
              ? "New screenshots and recordings appear here automatically."
              : "Try a project name or screenshot filename."
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)],
            spacing: 14
          ) {
            ForEach(store.visibleItems) { item in
              CaptureLibraryCard(
                item: item,
                selected: item.id == selectionID,
                onSelect: { selectionID = item.id },
                onOpen: {
                  selectionID = item.id
                  store.open(item)
                }
              )
            }
          }
          .padding(16)
        }
      }
    }
  }

  private var searchBar: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(ReframedColors.secondaryText)
      TextField("Search captures", text: $store.query)
        .textFieldStyle(.plain)
        .font(.system(size: FontSize.sm))
      if !store.query.isEmpty {
        Button {
          store.query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(ReframedColors.secondaryText)
      }
    }
    .padding(.horizontal, 16)
    .frame(height: 52)
    .background(ReframedColors.backgroundPopover)
  }

  private func promptRename() {
    guard let item = selectedItem else { return }
    let alert = NSAlert()
    alert.messageText = "Rename \(item.kind.label.lowercased())"
    alert.informativeText = "Enter a new name."
    let field = NSTextField(string: item.title)
    field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
    alert.accessoryView = field
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    if store.rename(item, to: field.stringValue) {
      selectionID =
        store.items.first {
          $0.kind == item.kind && $0.title == field.stringValue
        }?.id
    }
  }

  private func deleteSelected() {
    guard let item = selectedItem, store.confirmDelete(item) else { return }
    selectionID = nil
  }
}

private struct CaptureLibraryCard: View {
  let item: CaptureLibraryItem
  let selected: Bool
  let onSelect: () -> Void
  let onOpen: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      LibraryThumbnail(item: item)
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay {
          RoundedRectangle(cornerRadius: Radius.md)
            .stroke(ReframedColors.border, lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
          Label(item.kind.label, systemImage: item.kind.icon)
            .labelStyle(.iconOnly)
            .font(.system(size: FontSize.xs, weight: .semibold))
            .padding(7)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: Radius.sm))
            .foregroundStyle(.white)
            .padding(7)
        }

      Text(item.title)
        .font(.system(size: FontSize.xs, weight: .semibold))
        .foregroundStyle(ReframedColors.primaryText)
        .lineLimit(1)

      HStack(spacing: 5) {
        Text(formatRelativeTime(item.createdAt))
        Text("·")
        Text(item.detail)
      }
      .font(.system(size: FontSize.xxs, weight: .medium))
      .foregroundStyle(ReframedColors.secondaryText)
      .lineLimit(1)
    }
    .padding(8)
    .background(ReframedColors.backgroundCard, in: RoundedRectangle(cornerRadius: Radius.md))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.md)
        .stroke(
          selected ? ReframedColors.primaryText.opacity(0.7) : ReframedColors.border,
          lineWidth: 1
        )
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 1, perform: onSelect)
    .onTapGesture(count: 2, perform: onOpen)
  }
}

private struct LibraryThumbnail: View {
  let item: CaptureLibraryItem
  @State private var image: NSImage?

  var body: some View {
    ZStack {
      ReframedColors.muted
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Image(systemName: item.kind.icon)
          .font(.system(size: FontSize.xxl))
          .foregroundStyle(ReframedColors.secondaryText)
      }
    }
    .clipped()
    .task(id: item.id) {
      image = await loadThumbnail()
    }
  }

  private func loadThumbnail() async -> NSImage? {
    switch item.kind {
    case .screenshot:
      return NSImage(contentsOf: item.fileURL)
    case .recording:
      let movURL = item.fileURL.appendingPathComponent("screen.mov")
      let mp4URL = item.fileURL.appendingPathComponent("screen.mp4")
      let videoURL =
        FileManager.default.fileExists(atPath: movURL.path)
        ? movURL
        : mp4URL
      if !FileManager.default.fileExists(atPath: videoURL.path) {
        return nil
      }
      let asset = AVURLAsset(url: videoURL)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 420, height: 260)
      do {
        let result = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        return NSImage(cgImage: result.image, size: .zero)
      } catch {
        return nil
      }
    }
  }
}

private struct InspectorView: View {
  let item: CaptureLibraryItem?
  let store: CaptureLibraryStore
  let onRename: () -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let item {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
              Text(item.kind.label.uppercased())
                .font(.system(size: FontSize.xxs, weight: .semibold))
                .foregroundStyle(ReframedColors.secondaryText)
              Text(item.title)
                .font(.system(size: FontSize.base, weight: .semibold))
                .foregroundStyle(ReframedColors.primaryText)
                .textSelection(.enabled)
            }

            detailRow(
              "Created",
              value: item.createdAt.formatted(date: .abbreviated, time: .shortened)
            )
            detailRow("Format", value: item.detail)
            detailRow("Location", value: item.fileURL.path)

            VStack(spacing: 8) {
              actionButton("Open", icon: "arrow.up.forward.app") {
                store.open(item)
              }
              actionButton("Rename", icon: "pencil", action: onRename)
              actionButton("Reveal in Finder", icon: "folder") {
                store.reveal(item)
              }
              if item.kind == .screenshot {
                actionButton("Copy", icon: "doc.on.doc") {
                  _ = store.copy(item)
                }
                actionButton("Save", icon: "square.and.arrow.down") {
                  _ = store.save(item)
                }
              }
              actionButton(
                "Move to Trash",
                icon: "trash",
                destructive: true,
                action: onDelete
              )
            }
          }
          .padding(16)
        }
      } else {
        VStack(spacing: 8) {
          Image(systemName: "sidebar.right")
            .font(.system(size: FontSize.xl))
          Text("Select a capture")
            .font(.system(size: FontSize.sm, weight: .medium))
        }
        .foregroundStyle(ReframedColors.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(ReframedColors.backgroundPopover)
  }

  private func detailRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.system(size: FontSize.xxs, weight: .semibold))
        .foregroundStyle(ReframedColors.secondaryText)
      Text(value)
        .font(.system(size: FontSize.xxs))
        .foregroundStyle(ReframedColors.primaryText)
        .lineLimit(3)
        .textSelection(.enabled)
    }
  }

  private func actionButton(
    _ title: String,
    icon: String,
    destructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon)
        .font(.system(size: FontSize.xs, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
          ReframedColors.buttonBackground,
          in: RoundedRectangle(cornerRadius: Radius.md)
        )
    }
    .buttonStyle(.plain)
    .foregroundStyle(destructive ? Color.red : ReframedColors.primaryText)
  }
}
