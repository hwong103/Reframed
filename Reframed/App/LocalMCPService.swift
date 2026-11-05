import AppKit
import Combine
import Foundation
import Network
import ScreenCaptureKit

enum LocalMCPListenerStatus: Equatable {
  case disabled
  case starting
  case listening
  case waiting(String)
  case failed(String)
}

@MainActor
final class LocalMCPService: ObservableObject {
  static let shared = LocalMCPService()

  private let queue = DispatchQueue(label: "eu.jankuri.reframed.local-mcp", qos: .userInitiated)
  private var listener: NWListener?
  private var listenerGeneration = LocalMCPListenerGeneration()
  private weak var session: SessionState?
  private var openLibrary: (() -> Void)?
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  private var requestBuffers: [ObjectIdentifier: Data] = [:]
  @Published private(set) var listenerStatus: LocalMCPListenerStatus = .disabled

  var endpointURL: String {
    "http://127.0.0.1:\(ConfigService.shared.localMCPPort)/mcp?token=\(token)"
  }

  var clientConfiguration: String {
    let configuration: [String: Any] = [
      "mcpServers": [
        "reframed": [
          "url": endpointURL
        ]
      ]
    ]
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: configuration,
        options: [.prettyPrinted, .sortedKeys]
      )
    else {
      return endpointURL
    }
    return String(decoding: data, as: UTF8.self)
  }

  func startIfEnabled(session: SessionState, openLibrary: @escaping () -> Void) {
    self.session = session
    self.openLibrary = openLibrary
    guard ConfigService.shared.localMCPEnabled else {
      listenerStatus = .disabled
      return
    }
    start()
  }

  func setEnabled(_ enabled: Bool) {
    ConfigService.shared.localMCPEnabled = enabled
    if enabled {
      start()
    } else {
      stop()
    }
  }

  func start() {
    guard listener == nil else { return }
    _ = token
    let configuredPort = ConfigService.shared.localMCPPort
    guard (1...Int(UInt16.max)).contains(configuredPort),
      let port = NWEndpoint.Port(rawValue: UInt16(configuredPort))
    else {
      listenerStatus = .failed("Invalid local MCP port \(configuredPort)")
      return
    }

    let generation = listenerGeneration.begin()
    listenerStatus = .starting
    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      parameters.includePeerToPeer = false
      parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
      let listener = try NWListener(using: parameters)
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in
          self?.accept(connection, generation: generation)
        }
      }
      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor in
          self?.updateListenerState(state, generation: generation)
        }
      }
      self.listener = listener
      listener.start(queue: queue)
    } catch {
      self.listener = nil
      listenerStatus = .failed("Could not start local MCP listener: \(error.localizedDescription)")
    }
  }

  func stop() {
    listenerGeneration.invalidate()
    listener?.cancel()
    listener = nil
    for connection in connections.values {
      connection.cancel()
    }
    connections.removeAll()
    requestBuffers.removeAll()
    listenerStatus = .disabled
  }

  private func updateListenerState(
    _ state: NWListener.State,
    generation: UInt64
  ) {
    guard listenerGeneration.accepts(generation) else { return }
    switch state {
    case .ready:
      listenerStatus = .listening
    case .waiting(let error):
      listenerStatus = .waiting(
        "Could not bind 127.0.0.1:\(ConfigService.shared.localMCPPort): \(error.localizedDescription)"
      )
    case .failed(let error):
      listenerGeneration.invalidate()
      listener?.cancel()
      listener = nil
      for connection in connections.values {
        connection.cancel()
      }
      connections.removeAll()
      requestBuffers.removeAll()
      listenerStatus = .failed(
        "Could not bind 127.0.0.1:\(ConfigService.shared.localMCPPort): \(error.localizedDescription)"
      )
    case .cancelled:
      break
    case .setup:
      listenerStatus = .starting
    @unknown default:
      listenerStatus = .starting
    }
  }

  private var token: String {
    if !ConfigService.shared.localMCPToken.isEmpty {
      return ConfigService.shared.localMCPToken
    }
    let created =
      UUID().uuidString.replacingOccurrences(of: "-", with: "")
      + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ConfigService.shared.localMCPToken = created
    return created
  }

  private func accept(_ connection: NWConnection, generation: UInt64) {
    guard listenerGeneration.accepts(generation) else {
      connection.cancel()
      return
    }
    let connectionID = ObjectIdentifier(connection)
    connections[connectionID] = connection
    requestBuffers[connectionID] = Data()
    connection.start(queue: queue)
    receive(on: connection)
  }

  private func receive(on connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, isComplete, error in
      Task { @MainActor in
        self?.received(
          data: data,
          isComplete: isComplete,
          error: error,
          connection: connection
        )
      }
    }
  }

  private func received(
    data: Data?,
    isComplete: Bool,
    error: NWError?,
    connection: NWConnection
  ) {
    let connectionID = ObjectIdentifier(connection)
    guard requestBuffers[connectionID] != nil else {
      connection.cancel()
      return
    }
    if let data {
      requestBuffers[connectionID, default: Data()].append(data)
      if requestBuffers[connectionID, default: Data()].count
        > LocalMCPHTTPParser.maxBufferedRequestBytes
      {
        respond(
          HTTPResponse.jsonError(status: 413, message: "Request body is too large"),
          on: connection
        )
        return
      }
    }

    if error != nil {
      finish(connection)
      return
    }

    guard let buffer = requestBuffers[connectionID] else { return }
    switch LocalMCPHTTPParser.parse(buffer) {
    case .failure(let parseError):
      requestBuffers.removeValue(forKey: connectionID)
      respond(
        HTTPResponse.jsonError(status: parseError.status, message: parseError.message),
        on: connection
      )
      return
    case .success(let request):
      if let request {
        requestBuffers.removeValue(forKey: connectionID)
        Task { @MainActor in
          await handle(request, on: connection)
        }
        return
      }
    }

    if isComplete {
      respond(
        HTTPResponse.jsonError(status: 400, message: "Incomplete HTTP request"),
        on: connection
      )
    } else {
      receive(on: connection)
    }
  }

  private func handle(_ request: LocalMCPHTTPRequest, on connection: NWConnection) async {
    guard request.method == "OPTIONS" || authorized(request) else {
      respond(.jsonError(status: 401, message: "Missing or invalid MCP token"), on: connection)
      return
    }
    if request.method == "OPTIONS" {
      respond(.empty(status: 204), on: connection)
      return
    }
    guard request.method == "POST", request.path == "/mcp" else {
      respond(.jsonError(status: 404, message: "Use POST /mcp"), on: connection)
      return
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
    else {
      respond(
        .jsonError(status: 400, message: "Request body must be a JSON object"),
        on: connection
      )
      return
    }

    let response = await handleJSONRPC(object)
    if let response {
      respond(.json(response), on: connection)
    } else {
      respond(.empty(status: 202), on: connection)
    }
  }

  private func authorized(_ request: LocalMCPHTTPRequest) -> Bool {
    if request.headers["authorization"] == "Bearer \(token)" {
      return true
    }
    guard
      let components = URLComponents(string: "http://127.0.0.1\(request.target)"),
      let supplied = components.queryItems?.first(where: { $0.name == "token" })?.value
    else {
      return false
    }
    return supplied == token
  }

  private func handleJSONRPC(_ request: [String: Any]) async -> [String: Any]? {
    let method = request["method"] as? String ?? ""
    let requestID = request["id"]
    let params = request["params"] as? [String: Any] ?? [:]

    if requestID == nil, method.hasPrefix("notifications/") {
      return nil
    }

    do {
      let result: Any
      switch method {
      case "initialize":
        result = [
          "protocolVersion": "2025-06-18",
          "capabilities": [
            "tools": [
              "listChanged": false
            ]
          ],
          "serverInfo": [
            "name": "Reframed",
            "version": UpdateChecker.currentVersion,
          ],
        ]
      case "ping":
        result = [String: Any]()
      case "tools/list":
        result = ["tools": tools]
      case "tools/call":
        guard let name = params["name"] as? String else {
          throw MCPError("Missing tool name")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let toolResult = try await callTool(name, arguments: arguments)
        result = [
          "content": [
            [
              "type": "text",
              "text": toolResult,
            ]
          ],
          "structuredContent": [
            "result": toolResult
          ],
          "isError": false,
        ]
      default:
        return jsonRPCError(
          id: requestID,
          code: -32601,
          message: "Unknown method: \(method)"
        )
      }
      return [
        "jsonrpc": "2.0",
        "id": requestID ?? NSNull(),
        "result": result,
      ]
    } catch {
      return jsonRPCError(
        id: requestID,
        code: -32000,
        message: error.localizedDescription
      )
    }
  }

  private func callTool(_ name: String, arguments: [String: Any]) async throws -> String {
    switch name {
    case "list_recording_targets":
      return try await listRecordingTargets()
    case "start_recording":
      return try await startRecording(arguments: arguments)
    case "stop_recording":
      return try await stopRecording()
    case "record_agent_click":
      return try recordAgentClick(arguments: arguments)
    case "list_captures":
      return try jsonString(captureListPayload())
    case "open_library":
      openLibrary?()
      return try jsonString(["opened": true])
    case "get_project":
      let project = try resolveProject(arguments)
      return try jsonString(projectPayload(project))
    case "update_project":
      let project = try resolveProject(arguments)
      let patch = try requiredDictionary("patch", from: arguments)
      return try updateProject(project, patch: patch)
    case "export_project":
      let project = try resolveProject(arguments)
      return try await exportProject(project, arguments: arguments)
    case "open_project":
      let project = try resolveProject(arguments)
      try requireSession().openProject(at: project.bundleURL)
      return try jsonString([
        "project": project.name,
        "path": project.bundleURL.path,
        "opened": true,
      ])
    default:
      throw MCPError("Unknown tool: \(name)")
    }
  }

  private func requireSession() throws -> SessionState {
    guard let session else {
      throw MCPError("Reframed is not ready")
    }
    return session
  }

  private func captureListPayload() throws -> [[String: Any]] {
    let store = CaptureLibraryStore(session: try requireSession())
    store.refresh()
    return store.items.map { item in
      var payload: [String: Any] = [
        "id": item.id,
        "kind": item.kind.rawValue,
        "title": item.title,
        "path": item.fileURL.path,
        "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
        "detail": item.detail,
      ]
      if let width = item.width { payload["width"] = width }
      if let height = item.height { payload["height"] = height }
      return payload
    }
  }

  private func resolveProject(_ arguments: [String: Any]) throws -> ReframedProject {
    let store = CaptureLibraryStore(session: try requireSession())
    store.refresh()
    let candidates = store.items.compactMap { item -> (String, URL)? in
      guard item.kind == .recording else { return nil }
      return (item.id, item.fileURL)
    }

    let requestedID = (arguments["projectId"] as? String) ?? (arguments["id"] as? String)
    let requestedPath = arguments["path"] as? String
    let id =
      requestedID
      ?? requestedPath.map {
        CaptureLibraryStore.projectID(for: URL(fileURLWithPath: $0))
      }
    guard let id, let url = candidates.first(where: { $0.0 == id })?.1 else {
      throw MCPError("Project not found. Call list_captures first.")
    }
    return try ReframedProject.open(at: url)
  }

  private func projectPayload(_ project: ReframedProject) throws -> [String: Any] {
    let projectData = try Data(contentsOf: project.bundleURL.appendingPathComponent("project.json"))
    let document = try JSONSerialization.jsonObject(with: projectData)
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: project.bundleURL,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    let media = files.map { url -> [String: Any] in
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      return [
        "name": url.lastPathComponent,
        "bytes": size,
      ]
    }
    return [
      "id": CaptureLibraryStore.projectID(for: project.bundleURL),
      "name": project.name,
      "path": project.bundleURL.path,
      "document": document,
      "files": media,
    ]
  }

  private func updateProject(_ project: ReframedProject, patch: [String: Any]) throws -> String {
    let allowed = Set(["name", "editorState"])
    if let unsupported = patch.keys.first(where: { !allowed.contains($0) }) {
      throw MCPError("Unsupported top-level project field: \(unsupported)")
    }

    let projectURL = project.bundleURL.appendingPathComponent("project.json")
    let data = try Data(contentsOf: projectURL)
    guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw MCPError("project.json is not an object")
    }
    document = mergeDictionary(document, with: patch)

    let updatedData = try JSONSerialization.data(
      withJSONObject: document,
      options: [.prettyPrinted, .sortedKeys]
    )
    _ = try JSONDecoder.reframedProject.decode(ProjectMetadata.self, from: updatedData)
    try updatedData.write(to: projectURL, options: .atomic)

    return try jsonString([
      "saved": true,
      "projectId": CaptureLibraryStore.projectID(for: project.bundleURL),
      "name": document["name"] as? String ?? project.name,
    ])
  }

  private func exportProject(
    _ project: ReframedProject,
    arguments: [String: Any]
  ) async throws -> String {
    var settings = ExportSettings()
    switch (arguments["format"] as? String ?? "mp4").lowercased() {
    case "mp4": settings.format = .mp4
    case "mov": settings.format = .mov
    case "gif": settings.format = .gif
    default: throw MCPError("format must be mp4, mov, or gif")
    }
    if let fps = arguments["fps"] as? Int {
      switch fps {
      case 24: settings.fps = .fps24
      case 30: settings.fps = .fps30
      case 40: settings.fps = .fps40
      case 50: settings.fps = .fps50
      case 60: settings.fps = .fps60
      default: throw MCPError("Unsupported fps value")
      }
    }

    let state = EditorState(project: project)
    await state.setup(enableAutoSave: false)
    defer { state.teardown(persistChanges: false) }
    if arguments["autoZoom"] as? Bool == true {
      guard let clicks = state.cursorMetadataProvider?.metadata.clicks, !clicks.isEmpty else {
        throw MCPError("autoZoom requires cursor click metadata")
      }
      state.zoomEnabled = true
      state.autoZoomEnabled = true
      state.generateAutoZoom()
    }
    let exported = try await state.export(settings: settings)
    let finalURL: URL
    if let outputPath = arguments["outputPath"] as? String, !outputPath.isEmpty {
      let expanded = NSString(string: outputPath).expandingTildeInPath
      finalURL = URL(fileURLWithPath: expanded)
      guard !FileManager.default.fileExists(atPath: finalURL.path) else {
        throw MCPError("outputPath already exists")
      }
      try FileManager.default.createDirectory(
        at: finalURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try FileManager.default.moveToFinal(from: exported, to: finalURL)
    } else {
      finalURL = exported
    }

    let bytes =
      (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    return try jsonString([
      "exported": true,
      "projectId": CaptureLibraryStore.projectID(for: project.bundleURL),
      "path": finalURL.path,
      "bytes": bytes,
    ])
  }

  private func listRecordingTargets() async throws -> String {
    guard Permissions.hasScreenRecordingPermission else {
      throw MCPError(CaptureError.permissionDenied.localizedDescription)
    }

    let content = try await Permissions.fetchShareableContent()
    let displaysByID = Dictionary(
      uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) }
    )
    let screens = NSScreen.screens.compactMap { screen -> [String: Any]? in
      let displayID = screen.displayID
      guard let display = displaysByID[displayID] else { return nil }
      return screenTargetPayload(screen: screen, display: display)
    }
    let windows = content.windows
      .filter { isRecordableWindow($0) }
      .map { windowTargetPayload($0) }
      .sorted {
        (($0["applicationName"] as? String) ?? "")
          .localizedCaseInsensitiveCompare(
            ($1["applicationName"] as? String) ?? ""
          ) == .orderedAscending
      }

    return try jsonString([
      "coordinateSpace": recordingCoordinateSpace,
      "targets": screens + windows,
    ])
  }

  private func startRecording(arguments: [String: Any]) async throws -> String {
    guard let targetType = arguments["targetType"] as? String else {
      throw MCPError("targetType must be screen or window")
    }
    guard let targetID = arguments["targetId"] as? Int else {
      throw MCPError("targetId must be an integer from list_recording_targets")
    }

    let content = try await Permissions.fetchShareableContent()
    let selection: (target: CaptureTarget, mode: CaptureMode, payload: [String: Any])

    switch targetType {
    case "screen":
      guard let rawDisplayID = UInt32(exactly: targetID),
        let screen = NSScreen.screen(for: rawDisplayID),
        let display = content.displays.first(where: { $0.displayID == rawDisplayID })
      else {
        throw MCPError("Screen target is no longer available. Call list_recording_targets again.")
      }
      selection = (
        .region(SelectionRect(rect: screen.frame, displayID: rawDisplayID)),
        .entireScreen,
        screenTargetPayload(screen: screen, display: display)
      )
    case "window":
      guard let window = content.windows.first(where: { Int($0.windowID) == targetID }),
        isRecordableWindow(window)
      else {
        throw MCPError("Window target is no longer available. Call list_recording_targets again.")
      }
      selection = (.window(window), .selectedWindow, windowTargetPayload(window))
    default:
      throw MCPError("targetType must be screen or window")
    }

    let session = try requireSession()
    guard !session.isStartingRecording else {
      throw MCPError("Recording is already starting")
    }
    switch session.state {
    case .idle, .selecting, .countdown:
      break
    default:
      throw MCPError("Reframed is already recording or processing")
    }

    session.captureTarget = selection.target
    session.captureMode = selection.mode
    do {
      try await session.startRecording()
    } catch {
      if case .idle = session.state {
        session.captureTarget = nil
        session.captureMode = .none
      }
      throw error
    }

    return try jsonString([
      "coordinateSpace": recordingCoordinateSpace,
      "recording": true,
      "target": selection.payload,
    ])
  }

  private func stopRecording() async throws -> String {
    let session = try requireSession()
    guard let project = try await session.stopRecording() else {
      throw MCPError("Recording stopped without creating an exportable project")
    }
    return try jsonString([
      "stopped": true,
      "projectId": CaptureLibraryStore.projectID(for: project.bundleURL),
      "name": project.name,
      "path": project.bundleURL.path,
    ])
  }

  private func recordAgentClick(arguments: [String: Any]) throws -> String {
    let x = try requiredNumber("x", from: arguments)
    let y = try requiredNumber("y", from: arguments)
    let button = arguments["button"] as? Int ?? 0
    guard (0...1).contains(x), (0...1).contains(y) else {
      throw MCPError(
        "x and y must be normalized coordinates within the whole captured screen or window from 0 to 1"
      )
    }
    guard button == 0 || button == 1 else {
      throw MCPError("button must be 0 for left click or 1 for right click")
    }

    let session = try requireSession()
    guard case .recording = session.state else {
      throw MCPError("Agent clicks can only be recorded while recording")
    }
    guard
      let recorder = session.cursorMetadataRecorder,
      let timestamp = recorder.recordAgentClick(x: x, y: y, button: button)
    else {
      throw MCPError("Cursor metadata recording is not ready")
    }

    return try jsonString([
      "recorded": true,
      "time": timestamp,
      "x": x,
      "y": y,
      "button": button,
    ])
  }

  private func screenTargetPayload(
    screen: NSScreen,
    display: SCDisplay
  ) -> [String: Any] {
    [
      "type": "screen",
      "id": Int(display.displayID),
      "name": screen.localizedName,
      "width": display.width,
      "height": display.height,
      "isMain": (NSScreen.main?.displayID ?? 0) == screen.displayID,
    ]
  }

  private func windowTargetPayload(_ window: SCWindow) -> [String: Any] {
    let applicationName = window.owningApplication?.applicationName ?? "Unknown application"
    let trimmedTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
    var payload: [String: Any] = [
      "type": "window",
      "id": Int(window.windowID),
      "name": trimmedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? applicationName,
      "applicationName": applicationName,
      "width": Int(window.frame.width),
      "height": Int(window.frame.height),
    ]
    if let bundleIdentifier = window.owningApplication?.bundleIdentifier {
      payload["bundleIdentifier"] = bundleIdentifier
    }
    return payload
  }

  private var recordingCoordinateSpace: [String: Any] {
    [
      "name": "whole_capture",
      "origin": "top_left",
      "normalization": "x and y divided by the full captured screen or window dimensions",
      "viewportConversion": "not automatic",
    ]
  }

  private func isRecordableWindow(_ window: SCWindow) -> Bool {
    guard window.isOnScreen,
      window.frame.width >= 2,
      window.frame.height >= 2,
      let application = window.owningApplication
    else {
      return false
    }
    return application.bundleIdentifier != Bundle.main.bundleIdentifier
  }

  private func requiredDictionary(
    _ key: String,
    from arguments: [String: Any]
  ) throws -> [String: Any] {
    guard let value = arguments[key] as? [String: Any] else {
      throw MCPError("\(key) must be an object")
    }
    return value
  }

  private func requiredNumber(
    _ key: String,
    from arguments: [String: Any]
  ) throws -> Double {
    guard let value = arguments[key] as? NSNumber else {
      throw MCPError("\(key) must be a number")
    }
    return value.doubleValue
  }

  private func jsonString(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(
      withJSONObject: object,
      options: [.prettyPrinted, .sortedKeys]
    )
    return String(decoding: data, as: UTF8.self)
  }

  private func mergeDictionary(
    _ original: [String: Any],
    with patch: [String: Any]
  ) -> [String: Any] {
    var result = original
    for (key, value) in patch {
      if value is NSNull {
        result.removeValue(forKey: key)
      } else if let patchObject = value as? [String: Any],
        let originalObject = result[key] as? [String: Any]
      {
        result[key] = mergeDictionary(originalObject, with: patchObject)
      } else {
        result[key] = value
      }
    }
    return result
  }

  private func jsonRPCError(id: Any?, code: Int, message: String) -> [String: Any] {
    [
      "jsonrpc": "2.0",
      "id": id ?? NSNull(),
      "error": [
        "code": code,
        "message": message,
      ],
    ]
  }

  private var tools: [[String: Any]] {
    [
      tool(
        name: "list_recording_targets",
        description:
          "Lists the on-screen displays and application windows that the agent can record.",
        properties: [:]
      ),
      tool(
        name: "start_recording",
        description:
          "Starts recording a screen or window from list_recording_targets. Returns after a video frame is confirmed.",
        properties: [
          "targetType": [
            "type": "string",
            "enum": ["screen", "window"],
          ],
          "targetId": [
            "type": "integer",
            "description": "The id returned by list_recording_targets.",
          ],
        ],
        required: ["targetType", "targetId"]
      ),
      tool(
        name: "stop_recording",
        description:
          "Stops the active Reframed recording and returns the new project id for editing or export.",
        properties: [:]
      ),
      tool(
        name: "record_agent_click",
        description:
          "Reports an agent-driven click using coordinates for the whole captured screen or window, including browser or application chrome. x and y are normalized from 0 to 1, top-left to bottom-right. Viewport-relative coordinates must be converted to whole-window coordinates first; Reframed does not perform this conversion. This records the click and virtual cursor for auto-zoom.",
        properties: [
          "x": [
            "type": "number",
            "minimum": 0,
            "maximum": 1,
          ],
          "y": [
            "type": "number",
            "minimum": 0,
            "maximum": 1,
          ],
          "button": [
            "type": "integer",
            "enum": [0, 1],
            "description": "0 for left click, 1 for right click.",
          ],
        ],
        required: ["x", "y"]
      ),
      tool(
        name: "list_captures",
        description: "Lists local Reframed screenshots and recording projects, newest first.",
        properties: [:]
      ),
      tool(
        name: "open_library",
        description: "Opens Reframed's local Capture Library window.",
        properties: [:]
      ),
      tool(
        name: "get_project",
        description: "Returns a recording project's project.json document and files.",
        properties: [
          "projectId": ["type": "string", "description": "The project id from list_captures."]
        ],
        required: ["projectId"]
      ),
      tool(
        name: "update_project",
        description:
          "Saves a JSON merge patch at project.json. Only top-level name and editorState are writable; the result is decoded as ProjectMetadata before it is written.",
        properties: [
          "projectId": ["type": "string"],
          "patch": [
            "type": "object",
            "description": "A partial object containing name and/or editorState.",
          ],
        ],
        required: ["projectId", "patch"]
      ),
      tool(
        name: "export_project",
        description:
          "Renders a recording project with its saved editor state and returns the exported file path.",
        properties: [
          "projectId": ["type": "string"],
          "format": ["type": "string", "enum": ["mp4", "mov", "gif"]],
          "fps": ["type": "integer", "enum": [24, 30, 40, 50, 60]],
          "autoZoom": [
            "type": "boolean",
            "description":
              "Generates click-based auto-zoom keyframes for this export without changing the project's saved editor settings.",
          ],
          "outputPath": [
            "type": "string",
            "description": "Optional absolute output file path. Existing files are rejected.",
          ],
        ],
        required: ["projectId"]
      ),
      tool(
        name: "open_project",
        description: "Opens a recording project in Reframed's editor.",
        properties: [
          "projectId": ["type": "string"]
        ],
        required: ["projectId"]
      ),
    ]
  }

  private func tool(
    name: String,
    description: String,
    properties: [String: Any],
    required: [String] = []
  ) -> [String: Any] {
    var schema: [String: Any] = [
      "type": "object",
      "properties": properties,
      "additionalProperties": false,
    ]
    if !required.isEmpty {
      schema["required"] = required
    }
    return [
      "name": name,
      "description": description,
      "inputSchema": schema,
    ]
  }

  private func respond(_ response: HTTPResponse, on connection: NWConnection) {
    connection.send(
      content: response.encoded(),
      completion: .contentProcessed { [weak self] _ in
        Task { @MainActor in
          self?.finish(connection)
        }
      }
    )
  }

  private func finish(_ connection: NWConnection) {
    let connectionID = ObjectIdentifier(connection)
    connections.removeValue(forKey: connectionID)
    requestBuffers.removeValue(forKey: connectionID)
    connection.cancel()
  }
}

private struct MCPError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

private struct HTTPResponse {
  let status: Int
  let contentType: String?
  let body: Data

  static func json(_ object: [String: Any]) -> HTTPResponse {
    let data =
      (try? JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys]
      )) ?? Data()
    return HTTPResponse(status: 200, contentType: "application/json", body: data)
  }

  static func jsonError(status: Int, message: String) -> HTTPResponse {
    let data =
      (try? JSONSerialization.data(
        withJSONObject: [
          "error": message
        ],
        options: [.sortedKeys]
      )) ?? Data()
    return HTTPResponse(status: status, contentType: "application/json", body: data)
  }

  static func empty(status: Int) -> HTTPResponse {
    HTTPResponse(status: status, contentType: nil, body: Data())
  }

  func encoded() -> Data {
    let reason: String
    switch status {
    case 200: reason = "OK"
    case 202: reason = "Accepted"
    case 204: reason = "No Content"
    case 400: reason = "Bad Request"
    case 401: reason = "Unauthorized"
    case 404: reason = "Not Found"
    case 413: reason = "Content Too Large"
    default: reason = "Error"
    }

    var headers = [
      "HTTP/1.1 \(status) \(reason)",
      "Connection: close",
      "Content-Length: \(body.count)",
      "Access-Control-Allow-Origin: *",
      "Access-Control-Allow-Headers: content-type, authorization, mcp-protocol-version",
      "Access-Control-Allow-Methods: POST, GET, OPTIONS",
    ]
    if let contentType {
      headers.append("Content-Type: \(contentType)")
    }
    let head = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    return head + body
  }
}

private extension JSONDecoder {
  static var reframedProject: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
