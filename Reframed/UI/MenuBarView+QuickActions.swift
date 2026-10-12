import SwiftUI

extension MenuBarView {
  private var screenshotsAvailable: Bool {
    if case .idle = session.state { return true }
    return false
  }

  private var gridColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
  }

  @ViewBuilder
  var quickActionsSection: some View {
    if permissionsGranted {
      Spacer().frame(height: 2)

      HoverEffectScope {
        LazyVGrid(columns: gridColumns, spacing: 6) {
          ActionGridItem(
            icon: "house",
            title: "Home",
            hoverId: "action.home"
          ) {
            onDismiss()
            session.showToolbar()
          }

          ActionGridItem(
            icon: "display",
            title: "Display",
            hoverId: "action.display"
          ) {
            onDismiss()
            guard case .idle = session.state else { return }
            session.showToolbar()
            session.selectMode(.entireScreen)
          }

          ActionGridItem(
            icon: "macwindow",
            title: "Window",
            hoverId: "action.window"
          ) {
            onDismiss()
            guard case .idle = session.state else { return }
            session.showToolbar()
            session.selectMode(.selectedWindow)
          }

          ActionGridItem(
            icon: "rectangle.dashed",
            title: "Area",
            hoverId: "action.area"
          ) {
            onDismiss()
            guard case .idle = session.state else { return }
            session.showToolbar()
            session.selectMode(.selectedArea)
          }
        }
      }
      .disabled(isBusy)
      .padding(.horizontal, 10)

      screenshotsGrid
    } else {
      PermissionsPrompt {
        onDismiss()
        onShowPermissions()
      }
    }
  }

  private var screenshotsGrid: some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionHeader(title: "Screenshots")

      HoverEffectScope {
        LazyVGrid(columns: gridColumns, spacing: 6) {
          ActionGridItem(
            icon: "crop",
            title: "Region",
            hoverId: "action.captureRegion",
            isEnabled: screenshotsAvailable
          ) {
            onDismiss()
            screenshotCoordinator.captureRegion()
          }

          ActionGridItem(
            icon: "camera",
            title: "Display",
            hoverId: "action.captureDisplay",
            isEnabled: screenshotsAvailable
          ) {
            onDismiss()
            screenshotCoordinator.captureDisplay()
          }

          ActionGridItem(
            icon: "arrow.counterclockwise",
            title: "Repeat",
            hoverId: "action.repeatLastCapture",
            isEnabled: screenshotsAvailable
          ) {
            onDismiss()
            screenshotCoordinator.repeatLast()
          }

          ActionGridItem(
            icon: "square.and.arrow.down",
            title: "Save",
            hoverId: "action.saveLastScreenshot",
            isEnabled: screenshotCoordinator.hasLastCapture
          ) {
            onDismiss()
            screenshotCoordinator.saveLastCapture()
          }
          .help("Save Last Screenshot")

          ActionGridItem(
            icon: "macwindow.on.rectangle",
            title: "Window",
            hoverId: "action.captureWindow",
            isEnabled: false
          ) {
            onDismiss()
          }
          .help("Window capture is not available yet.")
        }
      }
      .padding(.horizontal, 10)
    }
    .padding(.top, 10)
  }
}
