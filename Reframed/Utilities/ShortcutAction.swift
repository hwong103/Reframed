import AppKit
import Foundation

enum ShortcutAction: String, CaseIterable, Codable, Sendable {
  case switchToDisplay
  case switchToWindow
  case switchToArea
  case stopRecording
  case pauseResumeRecording
  case restartRecording
  case captureRegion
  case captureWindow
  case captureDisplay
  case repeatLastCapture
  case saveLastScreenshot
  case editorUndo
  case editorRedo

  var label: String {
    switch self {
    case .switchToDisplay: return "Display Mode"
    case .switchToWindow: return "Window Mode"
    case .switchToArea: return "Area Mode"
    case .stopRecording: return "Stop Recording"
    case .pauseResumeRecording: return "Pause / Resume"
    case .restartRecording: return "Restart Recording"
    case .captureRegion: return "Capture Region"
    case .captureWindow: return "Capture Window"
    case .captureDisplay: return "Capture Display"
    case .repeatLastCapture: return "Repeat Last Capture"
    case .saveLastScreenshot: return "Save Last Screenshot"
    case .editorUndo: return "Undo"
    case .editorRedo: return "Redo"
    }
  }

  var isSessionAction: Bool {
    switch self {
    case .editorUndo, .editorRedo:
      return false
    default:
      return true
    }
  }

  var isGlobal: Bool {
    switch self {
    case .switchToDisplay, .switchToWindow, .switchToArea:
      return false
    case .stopRecording, .pauseResumeRecording, .restartRecording:
      return true
    case .captureRegion, .captureWindow, .captureDisplay, .repeatLastCapture:
      return true
    case .saveLastScreenshot:
      return true
    case .editorUndo, .editorRedo:
      return false
    }
  }

  var defaultShortcut: KeyboardShortcut {
    let cmd = NSEvent.ModifierFlags.command.rawValue
    let shift = NSEvent.ModifierFlags.shift.rawValue
    let cmdShift = cmd | shift
    let optionShift = NSEvent.ModifierFlags.option.rawValue | shift

    switch self {
    case .switchToDisplay:
      return KeyboardShortcut(keyCode: 2, modifierFlags: cmdShift)
    case .switchToWindow:
      return KeyboardShortcut(keyCode: 13, modifierFlags: cmdShift)
    case .switchToArea:
      return KeyboardShortcut(keyCode: 0, modifierFlags: cmdShift)
    case .stopRecording:
      return KeyboardShortcut(keyCode: 1, modifierFlags: cmdShift)
    case .pauseResumeRecording:
      return KeyboardShortcut(keyCode: 35, modifierFlags: cmdShift)
    case .restartRecording:
      return KeyboardShortcut(keyCode: 15, modifierFlags: cmdShift)
    case .captureRegion:
      return KeyboardShortcut(keyCode: 23, modifierFlags: cmdShift)
    case .captureWindow:
      return KeyboardShortcut(keyCode: 23, modifierFlags: optionShift)
    case .captureDisplay:
      return KeyboardShortcut(keyCode: 20, modifierFlags: optionShift)
    case .repeatLastCapture:
      return KeyboardShortcut(keyCode: 15, modifierFlags: optionShift)
    case .saveLastScreenshot:
      return KeyboardShortcut(keyCode: 1, modifierFlags: optionShift)
    case .editorUndo:
      return KeyboardShortcut(keyCode: 6, modifierFlags: cmd)
    case .editorRedo:
      return KeyboardShortcut(keyCode: 6, modifierFlags: cmdShift)
    }
  }
}
