import AppKit

@MainActor
final class KeyboardShortcutManager {
  private weak var session: SessionState?
  private let screenshotCoordinator: ScreenshotCoordinator
  private var localMonitor: Any?
  private var eventTap: CFMachPort?
  private var tapRunLoopSource: CFRunLoopSource?
  private var tapContext: TapContext?

  private final class TapContext: @unchecked Sendable {
    weak var manager: KeyboardShortcutManager?
    var eventTap: CFMachPort?
  }

  init(session: SessionState, screenshotCoordinator: ScreenshotCoordinator) {
    self.session = session
    self.screenshotCoordinator = screenshotCoordinator
  }

  func start() {
    guard localMonitor == nil else { return }

    let context = TapContext()
    context.manager = self
    tapContext = context

    let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue
    if let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: Self.eventTapCallback,
      userInfo: Unmanaged.passUnretained(context).toOpaque()
    ) {
      context.eventTap = tap
      eventTap = tap
      let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
      tapRunLoopSource = source
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let session = self.session else { return event }

      if let responder = event.window?.firstResponder, responder is NSTextView {
        return event
      }

      for action in ShortcutAction.allCases where action.isSessionAction {
        let shortcut = ConfigService.shared.shortcut(for: action)
        if shortcut.matches(event) {
          self.performAction(action, on: session)
          return nil
        }
      }
      return event
    }
  }

  nonisolated private static let eventTapCallback: CGEventTapCallBack = {
    _,
    type,
    event,
    userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }

    let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout {
      if let tap = context.eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else { return Unmanaged.passUnretained(event) }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    nonisolated(unsafe) let unsafeEvent = event

    let consumed: Bool = MainActor.assumeIsolated {
      guard let manager = context.manager, let session = manager.session else {
        return false
      }

      for action in ShortcutAction.allCases where action.isGlobal {
        let shortcut = ConfigService.shared.shortcut(for: action)
        guard shortcut.matchesCGEvent(keyCode: keyCode, flags: flags) else { continue }
        guard manager.allowsGlobalAction(action, in: session) else { continue }
        manager.performAction(action, on: session)
        return true
      }
      return false
    }

    return consumed ? nil : Unmanaged.passUnretained(unsafeEvent)
  }

  func stop() {
    if let tapRunLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), tapRunLoopSource, .commonModes)
    }
    tapRunLoopSource = nil

    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    eventTap = nil
    tapContext = nil

    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
    }
    localMonitor = nil
  }

  private func performAction(_ action: ShortcutAction, on session: SessionState) {
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

    case .editorUndo, .editorRedo:
      return
    }
  }

  private func allowsGlobalAction(_ action: ShortcutAction, in session: SessionState) -> Bool {
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
    default:
      return false
    }
  }
}
