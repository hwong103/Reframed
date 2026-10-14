import AppKit
import ImageIO
import SwiftUI

struct RecentCaptureStrip: View {
  let captures: [RecentCaptureData]
  let onCopy: (RecentCaptureData) -> Void
  let onReveal: (RecentCaptureData) -> Void
  let onClear: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var isConfirmingClear = false

  private let rowHeight: CGFloat = 42

  var body: some View {
    let _ = colorScheme
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 0) {
        SectionHeader(title: isConfirmingClear ? "Clear all captures?" : "Recent Captures")
        clearControl
      }

      ScrollView {
        HoverEffectScope {
          LazyVStack(spacing: 0) {
            ForEach(captures) { capture in
              RecentCaptureRow(
                capture: capture,
                onCopy: { onCopy(capture) },
                onReveal: { onReveal(capture) }
              )
              .hoverEffect(id: "recent.\(capture.id)")
              .padding(.horizontal, 10)
            }
          }
        }
      }
      .frame(height: min(CGFloat(captures.count) * rowHeight, rowHeight * 5))
    }
    .padding(.top, 4)
  }

  @ViewBuilder
  private var clearControl: some View {
    if isConfirmingClear {
      HStack(spacing: 6) {
        clearButton("Keep", style: OutlineButtonStyle()) {
          isConfirmingClear = false
        }
        clearButton("Clear", style: PrimaryButtonStyle()) {
          isConfirmingClear = false
          onClear()
        }
      }
      .padding(.trailing, 8)
    } else {
      IconButton(systemName: "trash", color: ReframedColors.secondaryText) {
        isConfirmingClear = true
      }
      .help("Clear Recent Captures")
      .padding(.trailing, 8)
    }
  }

  private func clearButton(
    _ title: String,
    style: some ButtonStyle,
    action: @escaping () -> Void
  )
    -> some View
  {
    Button(action: action) {
      Text(title)
        .font(.system(size: FontSize.xxs, weight: .medium))
    }
    .buttonStyle(style)
  }
}

private struct RecentCaptureRow: View {
  let capture: RecentCaptureData
  let onCopy: () -> Void
  let onReveal: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let _ = colorScheme
    HStack(spacing: 8) {
      Button(action: onCopy) {
        HStack(spacing: 10) {
          thumbnail
          details
          Spacer(minLength: 0)
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
      }
      .buttonStyle(PlainCustomButtonStyle())
      .help("Copy to clipboard")

      IconButton(systemName: "folder", color: ReframedColors.secondaryText) {
        onReveal()
      }
      .help("Reveal in Finder")
    }
    .padding(.trailing, 8)
  }

  private var rowHeight: CGFloat { 32 }

  private var details: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(capture.filename)
        .font(.system(size: FontSize.xxs, weight: .medium))
        .foregroundStyle(ReframedColors.primaryText)
        .lineLimit(1)
        .truncationMode(.middle)

      Text(relativeTime)
        .font(.system(size: FontSize.xxs, weight: .medium))
        .foregroundStyle(ReframedColors.secondaryText)
    }
  }

  private var relativeTime: String {
    "\(formatRelativeTime(capture.date)) \u{00b7} \(capture.width) \u{00d7} \(capture.height)"
  }

  private var thumbnail: some View {
    Group {
      if let image = RecentCaptureThumbnail.image(for: capture) {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Image(systemName: "photo")
          .font(.system(size: FontSize.xs))
          .foregroundStyle(ReframedColors.secondaryText)
      }
    }
    .frame(width: rowHeight * 1.4, height: rowHeight)
    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    .background(ReframedColors.muted)
  }
}

private enum RecentCaptureThumbnail {
  static func image(for capture: RecentCaptureData) -> NSImage? {
    let url = RecentCaptureStore.shared.fileURL(for: capture.id)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 128,
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
  }
}
