import Foundation

@MainActor
struct WindowSelectionRequest {
  let confirmTitle: String
  let hint: String
  let onConfirm: (WindowInfo) -> Void
  let onCancel: () -> Void
}
