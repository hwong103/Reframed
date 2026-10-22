import ServiceManagement
import SwiftUI

extension SettingsView {
  var generalContent: some View {
    Group {
      settingsRow(label: "Appearance") {
        SegmentPicker(
          items: ["system", "light", "dark"],
          label: { $0.capitalized },
          selection: Binding(
            get: { appearance },
            set: {
              appearance = $0
              ConfigService.shared.appearance = $0
              updateWindowBackgrounds()
            }
          )
        )
      }

      settingsToggle(
        "Open Reframed at Login",
        isOn: Binding(
          get: { launchAtLoginEnabled },
          set: { setLaunchAtLogin($0) }
        )
      )

      if SMAppService.mainApp.status == .requiresApproval {
        HStack {
          Text("Allow Reframed in System Settings > General > Login Items.")
            .font(.system(size: FontSize.xs))
            .foregroundStyle(ReframedColors.secondaryText)
          Spacer()
          Button("Open Login Items") {
            SMAppService.openSystemSettingsLoginItems()
          }
          .buttonStyle(OutlineButtonStyle(size: .small))
        }
        .padding(.top, -10)
      }

      if let launchAtLoginError {
        Text(launchAtLoginError)
          .font(.system(size: FontSize.xs))
          .foregroundStyle(ReframedColors.secondaryText)
          .padding(.top, -10)
      }

      settingsRow(label: "Project Folder") {
        HStack(spacing: 8) {
          Text(projectFolder)
            .font(.system(size: FontSize.xs))
            .foregroundStyle(ReframedColors.primaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ReframedColors.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(ReframedColors.border))

          Button("Browse") {
            chooseProjectFolder()
          }
          .buttonStyle(OutlineButtonStyle(size: .small))
        }
      }

      settingsRow(label: "Output Folder") {
        HStack(spacing: 8) {
          Text(outputFolder)
            .font(.system(size: FontSize.xs))
            .foregroundStyle(ReframedColors.primaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ReframedColors.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(ReframedColors.border))

          Button("Browse") {
            chooseOutputFolder()
          }
          .buttonStyle(OutlineButtonStyle(size: .small))
        }
      }

      settingsToggle(
        "Remember Last Selection",
        isOn: Binding(
          get: { options?.rememberLastSelection ?? false },
          set: { options?.rememberLastSelection = $0 }
        )
      )

      settingsToggle(
        "Dim Outer Area While Recording",
        isOn: Binding(
          get: { options?.dimOuterArea ?? true },
          set: { options?.dimOuterArea = $0 }
        )
      )

      settingsToggle(
        "Hide Camera Preview While Recording",
        isOn: Binding(
          get: { options?.hideCameraPreviewWhileRecording ?? false },
          set: { options?.hideCameraPreviewWhileRecording = $0 }
        )
      )

      settingsToggle(
        "Show Recording Preview",
        isOn: Binding(
          get: { options?.showRecordingPreview ?? false },
          set: { options?.showRecordingPreview = $0 }
        )
      )
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      refreshLaunchAtLoginStatus()
      launchAtLoginError = nil
    } catch {
      refreshLaunchAtLoginStatus()
      launchAtLoginError = "Could not update login settings: \(error.localizedDescription)"
    }
  }

  func refreshLaunchAtLoginStatus() {
    let status = SMAppService.mainApp.status
    launchAtLoginEnabled = status == .enabled || status == .requiresApproval
    if status == .enabled {
      launchAtLoginError = nil
    }
  }
}
