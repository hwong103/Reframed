import AppKit

extension KeyboardShortcutManager {
  func performAction(_ action: ShortcutAction, on session: SessionState) {
    switch action {
    case .switchToDisplay:
      guard case .idle = session.state else { return }
      session.selectMode(.entireScreen)

    case .switchToWindow:
      guard case .idle = session.state else { return }
      session.selectMode(.selectedWindow)

    case .switchToArea:
      guard case .idle = session.state else { return }
      session.selectMode(.selectedArea)

    case .stopRecording:
      switch session.state {
      case .recording, .paused:
        Task {
          try? await session.stopRecording()
        }
      default:
        break
      }

    case .pauseResumeRecording:
      switch session.state {
      case .recording:
        session.pauseRecording()
      case .paused:
        session.resumeRecording()
      default:
        break
      }

    case .restartRecording:
      switch session.state {
      case .recording, .paused, .countdown:
        session.restartRecording()
      default:
        break
      }

    case .captureRegion:
      screenshotCoordinator.captureRegion()

    case .captureWindow:
      screenshotCoordinator.captureWindow()

    case .captureDisplay:
      screenshotCoordinator.captureDisplay()

    case .repeatLastCapture:
      screenshotCoordinator.repeatLast()

    case .saveLastScreenshot:
      screenshotCoordinator.saveLastCapture()

    case .textSnip:
      screenshotCoordinator.captureTextSnip()

    case .pinLastScreenshot:
      screenshotCoordinator.pinLastCapture()

    case .editorUndo, .editorRedo:
      return
    }
  }

  func allowsGlobalAction(_ action: ShortcutAction, in session: SessionState) -> Bool {
    switch action {
    case .stopRecording, .pauseResumeRecording, .restartRecording:
      switch session.state {
      case .countdown, .recording, .paused:
        return true
      default:
        return false
      }
    case .captureRegion, .captureWindow, .captureDisplay, .repeatLastCapture:
      return true
    case .saveLastScreenshot, .pinLastScreenshot:
      return screenshotCoordinator.hasLastCapture
    case .textSnip:
      return true
    default:
      return false
    }
  }
}
