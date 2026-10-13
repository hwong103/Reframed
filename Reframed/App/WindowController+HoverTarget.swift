import AppKit
import ApplicationServices

struct HoverTarget: Equatable {
  let bounds: CGRect
  let title: String?
  let windowID: CGWindowID
}

enum HoverTargetSnapshot {
  static func current() -> [HoverTarget] {
    let myPID = ProcessInfo.processInfo.processIdentifier
    guard
      let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else { return [] }

    return windowList.compactMap { windowDict in
      guard let pid = windowDict[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
        let boundsDict = windowDict[kCGWindowBounds as String],
        let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
        bounds.width > 8, bounds.height > 8
      else { return nil }

      let windowNumber = windowDict[kCGWindowNumber as String] as? Int ?? 0
      let rawTitle = windowDict[kCGWindowName as String] as? String
      return HoverTarget(
        bounds: bounds,
        title: (rawTitle?.isEmpty == false) ? rawTitle : nil,
        windowID: CGWindowID(windowNumber)
      )
    }
  }
}

extension WindowController {
  func findOnScreenTarget(at point: CGPoint) -> HoverTarget? {
    let myPID = ProcessInfo.processInfo.processIdentifier
    guard
      let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else { return nil }

    for windowDict in windowList {
      guard let pid = windowDict[kCGWindowOwnerPID as String] as? pid_t,
        pid != myPID,
        let boundsDict = windowDict[kCGWindowBounds as String],
        let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
        bounds.width > 8,
        bounds.height > 8,
        bounds.contains(point)
      else { continue }

      let windowNumber = windowDict[kCGWindowNumber as String] as? Int ?? 0
      let rawTitle = windowDict[kCGWindowName as String] as? String
      return HoverTarget(
        bounds: bounds,
        title: (rawTitle?.isEmpty == false) ? rawTitle : nil,
        windowID: CGWindowID(windowNumber)
      )
    }

    return nil
  }

  func onScreenWindows(layerZeroOnly: Bool) -> [[String: Any]] {
    let myPID = ProcessInfo.processInfo.processIdentifier
    guard
      let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else { return [] }

    return windowList.filter { windowDict in
      guard let pid = windowDict[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
        let boundsDict = windowDict[kCGWindowBounds as String],
        let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
        bounds.width > 20, bounds.height > 20
      else { return false }
      guard layerZeroOnly else { return true }
      return (windowDict[kCGWindowLayer as String] as? Int) == 0
    }
  }

  func info(for windowDict: [String: Any]) -> WindowInfo {
    let pid = windowDict[kCGWindowOwnerPID as String] as? pid_t ?? 0
    let boundsDict = windowDict[kCGWindowBounds as String] as! CFDictionary
    let bounds = CGRect(dictionaryRepresentation: boundsDict) ?? .zero
    let windowNumber = windowDict[kCGWindowNumber as String] as? Int ?? 0
    let title = windowDict[kCGWindowName as String] as? String ?? ""
    let app = NSRunningApplication(processIdentifier: pid)
    let appName = app?.localizedName ?? "Unknown"

    let axApp = AXUIElementCreateApplication(pid)
    let axWindow = findAXWindow(for: axApp, matching: bounds) ?? axApp

    let matchedID: Int
    if let match = scWindows.first(where: { $0.windowID == CGWindowID(windowNumber) }) {
      matchedID = Int(match.windowID)
    } else {
      matchedID = windowNumber
    }

    return WindowInfo(
      id: matchedID,
      frame: bounds,
      title: title,
      appPID: pid,
      appName: appName,
      axElement: axWindow
    )
  }
}
