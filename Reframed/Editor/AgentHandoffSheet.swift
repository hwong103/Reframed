import AVFoundation
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftUI

private struct AgentHandoffManifest: Encodable {
  struct Frame: Encodable {
    let timeSeconds: Double
    let path: String
  }

  let formatVersion: Int
  let projectName: String
  let task: String
  let durationSeconds: Double
  let video: String?
  let contactSheet: String
  let frames: [Frame]
  let transcript: String?
  let transcriptStatus: String
}

struct AgentHandoffSheet: View {
  @Bindable var editorState: EditorState
  @Binding var isPresented: Bool
  @State private var taskNotes = ""
  @State private var frameCount = 8
  @State private var includeVideo = true
  @State private var includeTranscript = false
  @State private var isCreating = false
  @State private var progress = 0.0
  @State private var status = ""
  @State private var errorMessage: String?
  @State private var createdFolder: URL?
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let _ = colorScheme
    VStack(alignment: .leading, spacing: 18) {
      Text(createdFolder == nil ? "Create Agent Handoff" : "Handoff Ready")
        .font(.system(size: FontSize.xxl, weight: .semibold))
        .foregroundStyle(ReframedColors.primaryText)

      if let createdFolder {
        Text("A portable folder is ready for Codex or Claude Code. Remote chats need you to attach the files manually.")
          .font(.system(size: FontSize.sm))
          .foregroundStyle(ReframedColors.secondaryText)
        HStack {
          Button("Copy for Codex") { copyInstructions(for: "Codex") }
            .buttonStyle(OutlineButtonStyle(size: .small))
          Button("Copy for Claude Code") { copyInstructions(for: "Claude Code") }
            .buttonStyle(OutlineButtonStyle(size: .small))
          Spacer()
          Button("Reveal Folder") {
            NSWorkspace.shared.activateFileViewerSelecting([createdFolder])
          }
          .buttonStyle(PrimaryButtonStyle(size: .small))
        }
        if !status.isEmpty {
          Text(status)
            .font(.system(size: FontSize.xs))
            .foregroundStyle(ReframedColors.secondaryText)
        }
        HStack {
          Spacer()
          Button("Done") { isPresented = false }
            .buttonStyle(OutlineButtonStyle(size: .small))
        }
      } else {
        Text("Creates a local folder with the edited video and up to 12 timestamped frames. Nothing is uploaded or sent to an agent.")
          .font(.system(size: FontSize.sm))
          .foregroundStyle(ReframedColors.secondaryText)

        TextField("What should the agent inspect?", text: $taskNotes, axis: .vertical)
          .lineLimit(3...5)
          .textFieldStyle(.roundedBorder)

        Stepper("Frames: \(frameCount)", value: $frameCount, in: 2...12)
        Toggle("Include edited MP4", isOn: $includeVideo)
          .toggleStyle(.checkbox)
        Toggle("Transcribe edited audio (uses a downloaded Whisper model)", isOn: $includeTranscript)
          .toggleStyle(.checkbox)

        if isCreating {
          ProgressView(value: editorState.isExporting ? editorState.exportProgress * 0.45 : progress)
          Text(status)
            .font(.system(size: FontSize.xs))
            .foregroundStyle(ReframedColors.secondaryText)
        }
        if let errorMessage {
          Text(errorMessage)
            .font(.system(size: FontSize.xs))
            .foregroundStyle(.red)
        }

        HStack {
          Button("Cancel", role: .cancel) { isPresented = false }
            .buttonStyle(OutlineButtonStyle(size: .small))
            .disabled(isCreating)
          Spacer()
          Button(isCreating ? "Creating…" : "Create Handoff…") { createHandoff() }
            .buttonStyle(PrimaryButtonStyle(size: .small))
            .disabled(isCreating || editorState.isExporting)
        }
      }
    }
    .padding(24)
    .frame(width: 520)
    .background(ReframedColors.backgroundPopover)
    .interactiveDismissDisabled(isCreating)
  }

  private func createHandoff() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Create Handoff Here"
    panel.message = "Choose a folder for the agent handoff."
    guard panel.runModal() == .OK, let parent = panel.url else { return }

    isCreating = true
    errorMessage = nil
    status = "Rendering edited recording…"
    progress = 0.02
    Task {
      do {
        createdFolder = try await AgentHandoffExporter.create(
          editorState: editorState,
          parent: parent,
          task: taskNotes,
          frameCount: frameCount,
          includeVideo: includeVideo,
          includeTranscript: includeTranscript,
          progress: { value, message in
            progress = value
            status = message
          }
        )
      } catch {
        errorMessage = error.localizedDescription
      }
      isCreating = false
    }
  }

  private func copyInstructions(for agent: String) {
    guard let createdFolder else { return }
    let readme = createdFolder.appendingPathComponent("README.md").path
    let prompt =
      "Inspect this Reframed recording handoff and help with the task in its README. Start with the contact sheet, then open relevant full-resolution frames. Cite frame timestamps in your findings. Handoff README: \(readme)"
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(prompt, forType: .string)
    status = "Copied a local handoff prompt for \(agent)."
  }
}

@MainActor
private enum AgentHandoffExporter {
  static func create(
    editorState: EditorState,
    parent: URL,
    task: String,
    frameCount: Int,
    includeVideo: Bool,
    includeTranscript: Bool,
    progress: @escaping (Double, String) -> Void
  ) async throws -> URL {
    let fm = FileManager.default
    var renderedURLToRemove: URL?
    defer {
      if let renderedURLToRemove {
        try? fm.removeItem(at: renderedURLToRemove)
      }
    }
    let staging = parent.appendingPathComponent(".reframed-handoff-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: staging.appendingPathComponent("frames"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: staging) }

    let settings = ExportSettings(
      format: .mp4,
      fps: .original,
      resolution: .original,
      codec: .h264,
      audioBitrate: .kbps192,
      mode: .parallel,
      captionExportMode: .burnIn
    )
    let renderedURL = try await editorState.export(settings: settings)
    renderedURLToRemove = renderedURL
    try Task.checkCancellation()
    let videoURL = staging.appendingPathComponent("recording.mp4")
    try fm.copyItem(at: renderedURL, to: videoURL)

    progress(0.45, "Extracting edited frames…")
    let asset = AVURLAsset(url: videoURL)
    let assetDuration = try await asset.load(.duration)
    let duration = max(0, CMTimeGetSeconds(assetDuration))
    guard duration.isFinite, duration > 0 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 2400, height: 2400)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let count = min(12, max(2, frameCount))
    let times = (0..<count).map { index in
      duration * Double(index) / Double(count - 1)
    }
    var frames: [AgentHandoffManifest.Frame] = []
    var images: [CGImage] = []
    for (index, seconds) in times.enumerated() {
      try Task.checkCancellation()
      let time = CMTime(seconds: min(seconds, max(0, duration - 0.05)), preferredTimescale: 600)
      let (image, actualTime) = try await generator.image(at: time)
      let outputSeconds = CMTimeGetSeconds(actualTime)
      let name = String(format: "frame-%03d.jpg", index + 1)
      let url = staging.appendingPathComponent("frames").appendingPathComponent(name)
      try writeJPEG(image, to: url, quality: 0.92)
      images.append(image)
      frames.append(.init(timeSeconds: outputSeconds, path: "frames/\(name)"))
      progress(0.45 + 0.35 * Double(index + 1) / Double(count), "Saving frame \(index + 1) of \(count)…")
    }
    let contactURL = staging.appendingPathComponent("contact-sheet.jpg")
    try writeContactSheet(images, frames: frames, to: contactURL)

    var transcriptPath: String?
    var transcriptStatus = "not_requested"
    if includeTranscript {
      let audioTracks = try await asset.loadTracks(withMediaType: .audio)
      if audioTracks.isEmpty {
        transcriptStatus = "no_audio"
      } else {
        let manager = WhisperModelManager.shared
        let preferredModel = WhisperModel(rawValue: editorState.captionModel)
        let model = ([preferredModel].compactMap { $0 } + [.turbo, .medium, .large, .base])
          .first(where: manager.isDownloaded)
        if let model, let modelPath = manager.modelPath(for: model) {
          progress(0.82, "Transcribing edited audio…")
          let audioURL = staging.appendingPathComponent("transcript-audio.m4a")
          guard
            let audioExport = AVAssetExportSession(
              asset: asset,
              presetName: AVAssetExportPresetAppleM4A
            )
          else {
            throw CocoaError(.fileWriteUnknown)
          }
          try await audioExport.export(to: audioURL, as: .m4a)
          let segments = try await TranscriptionService.transcribe(
            audioURL: audioURL,
            model: model,
            modelPath: modelPath
          )
          try fm.removeItem(at: audioURL)
          let contents = segments.map { segment in
            "[\(timestamp(segment.startSeconds))–\(timestamp(segment.endSeconds))] \(segment.text)"
          }.joined(separator: "\n")
          try contents.write(to: staging.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
          transcriptPath = "transcript.md"
          transcriptStatus = segments.isEmpty ? "completed_empty" : "completed"
        } else {
          transcriptStatus = "model_not_downloaded"
        }
      }
    }

    try Task.checkCancellation()
    if !includeVideo {
      try fm.removeItem(at: videoURL)
    }

    let manifest = AgentHandoffManifest(
      formatVersion: 1,
      projectName: editorState.projectName,
      task: task.trimmingCharacters(in: .whitespacesAndNewlines),
      durationSeconds: duration,
      video: includeVideo ? "recording.mp4" : nil,
      contactSheet: "contact-sheet.jpg",
      frames: frames,
      transcript: transcriptPath,
      transcriptStatus: transcriptStatus
    )
    let manifestData = try JSONEncoder.prettyPrinted.encode(manifest)
    try manifestData.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
    let readme = makeReadme(manifest)
    try readme.write(to: staging.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

    let folderName = "Agent Handoff - \(safeName(editorState.projectName))"
    var destination = parent.appendingPathComponent(folderName, isDirectory: true)
    var suffix = 2
    while fm.fileExists(atPath: destination.path) {
      destination = parent.appendingPathComponent("\(folderName) \(suffix)", isDirectory: true)
      suffix += 1
    }
    try fm.moveItem(at: staging, to: destination)
    progress(1, "Handoff created.")
    return destination
  }

  private static func makeReadme(_ manifest: AgentHandoffManifest) -> String {
    let task = manifest.task.isEmpty ? "No task notes provided." : manifest.task
    return """
      # Reframed agent handoff

      Project: \(manifest.projectName)
      Duration: \(timestamp(manifest.durationSeconds))

      ## Task

      \(task)

      ## Contents

      - `recording.mp4`: \(manifest.video == nil ? "not included." : "rendered from the edited timeline.")
      - `contact-sheet.jpg`: overview of \(manifest.frames.count) timestamped frames.
      - `frames/`: full-resolution frames sampled from the rendered video.
      - `transcript.md`: \(manifest.transcript.map { "edited-audio transcript at `\($0)`" } ?? "not included (status: `\(manifest.transcriptStatus)`).")
      - `manifest.json`: machine-readable paths, duration, and frame timestamps.

      All timestamps refer to the output timeline. Deleted source intervals and muted audio tracks are excluded by rendering before frame extraction and transcription.
      """
  }

  private static func safeName(_ name: String) -> String {
    let value = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "Recording" : value
  }

  private static func timestamp(_ seconds: Double) -> String {
    let value = max(0, seconds)
    return String(format: "%02d:%05.2f", Int(value / 60), value.truncatingRemainder(dividingBy: 60))
  }

  private static func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
  }

  private static func writeContactSheet(
    _ images: [CGImage],
    frames: [AgentHandoffManifest.Frame],
    to url: URL
  ) throws {
    let columns = 3
    let cellWidth = 480
    let cellHeight = 300
    let rows = Int(ceil(Double(images.count) / Double(columns)))
    guard
      let context = CGContext(
        data: nil,
        width: columns * cellWidth,
        height: rows * cellHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
    else { throw CocoaError(.fileWriteUnknown) }
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: columns * cellWidth, height: rows * cellHeight))
    for (index, image) in images.enumerated() {
      let column = index % columns
      let row = index / columns
      let bounds = CGRect(x: column * cellWidth, y: (rows - row - 1) * cellHeight, width: cellWidth, height: cellHeight - 34)
      let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
      let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
      let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
      context.draw(image, in: rect)
      let label = NSAttributedString(
        string: timestamp(frames[index].timeSeconds),
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Menlo" as CFString, 18, nil),
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.white.cgColor,
        ]
      )
      context.textPosition = CGPoint(x: column * cellWidth + 10, y: (rows - row - 1) * cellHeight + 8)
      CTLineDraw(CTLineCreateWithAttributedString(label), context)
    }
    guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    try writeJPEG(image, to: url, quality: 0.88)
  }
}

private extension JSONEncoder {
  static var prettyPrinted: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
