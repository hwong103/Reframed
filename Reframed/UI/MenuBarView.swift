import AVFoundation
import AppKit
import SwiftUI

struct MenuBarView: View {
  let session: SessionState
  let screenshotCoordinator: ScreenshotCoordinator
  let onDismiss: () -> Void
  let onShowPermissions: () -> Void

  @State var recentProjects: [RecentProject] = []
  @State var recentCaptures: [RecentCaptureData] = []
  @State var totalProjectCount: Int = 0
  @State var permissionsGranted = Permissions.allPermissionsGranted
  @Environment(\.colorScheme) private var colorScheme

  private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var isBusy: Bool {
    if case .idle = session.state { return false }
    if case .editing = session.state { return false }
    return true
  }

  var body: some View {
    let _ = colorScheme
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        if permissionsGranted {
          SectionHeader(title: "Quick Actions")
        }
        Spacer()
        Text("v\(UpdateChecker.currentVersion)")
          .font(.system(size: FontSize.xxs, weight: .medium))
          .foregroundStyle(ReframedColors.secondaryText)
          .padding(.horizontal, 12)
          .padding(.top, 8)
      }

      quickActionsSection

      MenuBarDivider()

      Text(totalProjectCount > 0 ? "Projects (\(totalProjectCount))" : "Projects")
        .font(.system(size: FontSize.xxs, weight: .semibold))
        .foregroundStyle(ReframedColors.secondaryText)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)

      if recentProjects.isEmpty {
        Text("No recent projects")
          .font(.system(size: FontSize.xs))
          .foregroundStyle(ReframedColors.secondaryText)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 12)
      } else {
        ScrollView {
          HoverEffectScope {
            LazyVStack(spacing: 0) {
              ForEach(recentProjects) { project in
                ProjectRow(project: project) {
                  onDismiss()
                  session.openProject(at: project.url)
                }
                .hoverEffect(id: "project.\(project.id)")
                .disabled(isBusy)
                .padding(.horizontal, 10)
              }
            }
          }
        }
        .frame(height: min(CGFloat(recentProjects.count) * 46, 46 * 6))
      }

      MenuBarDivider()

      if !recentCaptures.isEmpty {
        recentCapturesSection

        MenuBarDivider()
      }

      HoverEffectScope {
        HStack(spacing: 0) {
          Button {
            onDismiss()
            let path = (ConfigService.shared.projectFolder as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
          } label: {
            Text("Open Projects")
              .font(.system(size: FontSize.xxs, weight: .medium))
              .foregroundStyle(ReframedColors.primaryText)
              .frame(maxWidth: .infinity)
              .frame(height: 42)
              .contentShape(Rectangle())
          }
          .buttonStyle(PlainCustomButtonStyle())
          .hoverEffect(id: "openFolder")

          Button {
            onDismiss()
            NSApp.terminate(nil)
          } label: {
            HStack(spacing: 4) {
              Text("Quit")
                .font(.system(size: FontSize.xxs, weight: .medium))
                .foregroundStyle(ReframedColors.primaryText)
              Text("\u{2318}Q")
                .font(.system(size: FontSize.xxs - 1, weight: .medium))
                .foregroundStyle(ReframedColors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(Rectangle())
          }
          .buttonStyle(PlainCustomButtonStyle())
          .hoverEffect(id: "quit")
        }
        .padding(.horizontal, 10)
      }

    }
    .padding(.vertical, 8)
    .frame(width: Layout.menuBarWidth)
    .background(ReframedColors.backgroundPopover)
    .task {
      await loadRecentProjects()
    }
    .onAppear {
      recentCaptures = RecentCaptureStore.shared.captures
    }
    .onReceive(permissionTimer) { _ in
      permissionsGranted = Permissions.allPermissionsGranted
    }
  }

  private var recentCapturesSection: some View {
    RecentCaptureStrip(
      captures: recentCaptures,
      onCopy: { capture in
        let copied = RecentCaptureStore.shared.copyToClipboard(capture)
        onDismiss()
        ScreenshotFeedbackWindow.show(
          copied ? "Copied to clipboard" : "Could not copy that capture",
          detail: copied ? "\(capture.width) \u{00d7} \(capture.height) px" : capture.filename,
          near: NSEvent.mouseLocation
        )
      },
      onSave: { capture in
        let saved = RecentCaptureStore.shared.save(capture)
        onDismiss()
        ScreenshotFeedbackWindow.show(
          saved == nil ? "Could not save that capture" : "Screenshot saved",
          detail: saved?.lastPathComponent ?? capture.filename,
          near: NSEvent.mouseLocation
        )
      },
      onReveal: { capture in
        onDismiss()
        RecentCaptureStore.shared.reveal(capture)
      },
      onClear: {
        RecentCaptureStore.shared.clear()
        recentCaptures = []
      }
    )
  }
}
