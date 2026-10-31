import AppKit
import Foundation
import Network

@MainActor
final class LocalMCPService {
  static let shared = LocalMCPService()

  private let queue = DispatchQueue(label: "eu.jankuri.reframed.local-mcp", qos: .userInitiated)
  private let tokenDefaultsKey = "ReframedLocalMCPToken"
  private var listener: NWListener?
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  private var requestBuffers: [ObjectIdentifier: Data] = [:]

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

  func startIfEnabled() {
    guard ConfigService.shared.localMCPEnabled else { return }
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
    guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: ConfigService.shared.localMCPPort))
    else { return }

    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    parameters.requiredInterfaceType = .loopback
    parameters.includePeerToPeer = false

    do {
      let listener = try NWListener(using: parameters, on: port)
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in
          self?.accept(connection)
        }
      }
      listener.stateUpdateHandler = { state in
        guard case .failed = state else { return }
        Task { @MainActor in
          LocalMCPService.shared.stop()
        }
      }
      listener.start(queue: queue)
      self.listener = listener
    } catch {
      self.listener = nil
    }
  }

  func stop() {
    listener?.cancel()
    listener = nil
    for connection in connections.values {
      connection.cancel()
    }
    connections.removeAll()
    requestBuffers.removeAll()
  }

  private var token: String {
    if let existing = UserDefaults.standard.string(forKey: tokenDefaultsKey), !existing.isEmpty {
      return existing
    }
    let created =
      UUID().uuidString.replacingOccurrences(of: "-", with: "")
      + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    UserDefaults.standard.set(created, forKey: tokenDefaultsKey)
    return created
  }

  private func accept(_ connection: NWConnection) {
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
      if requestBuffers[connectionID, default: Data()].count > 8 * 1024 * 1024 {
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

    if let request = parseBufferedRequest(connectionID: connectionID) {
      requestBuffers.removeValue(forKey: connectionID)
      Task { @MainActor in
        await handle(request, on: connection)
      }
      return
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

  private func parseBufferedRequest(connectionID: ObjectIdentifier) -> HTTPRequest? {
    guard let buffer = requestBuffers[connectionID] else { return nil }
    let delimiter = Data("\r\n\r\n".utf8)
    guard let headerRange = buffer.range(of: delimiter) else { return nil }

    let headerData = buffer[..<headerRange.lowerBound]
    guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
    let lines = headerText.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else { return nil }
    let requestParts = requestLine.split(separator: " ")
    guard requestParts.count >= 2 else { return nil }

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let separator = line.firstIndex(of: ":") else { continue }
      let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
      let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      headers[key] = value
    }

    let contentLength = Int(headers["content-length"] ?? "0") ?? 0
    let bodyStart = headerRange.upperBound
    guard buffer.count >= bodyStart + contentLength else { return nil }
    let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))

    return HTTPRequest(
      method: String(requestParts[0]),
      target: String(requestParts[1]),
      headers: headers,
      body: body
    )
  }

  private func handle(_ request: HTTPRequest, on connection: NWConnection) async {
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

  private func authorized(_ request: HTTPRequest) -> Bool {
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
    case "list_captures":
      return try jsonString(captureListPayload())
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
      session.openProject(at: project.bundleURL)
      return try jsonString([
        "project": project.name,
        "path": project.bundleURL.path,
        "opened": true,
      ])
    default:
      throw MCPError("Unknown tool: \(name)")
    }
  }

  private var session: SessionState {
    (NSApplication.shared.delegate as! AppDelegate).session
  }

  private func captureListPayload() -> [[String: Any]] {
    let store = CaptureLibraryStore(session: session)
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
    let store = CaptureLibraryStore(session: session)
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
    await state.setup()
    defer { state.teardown() }
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

  private func requiredDictionary(
    _ key: String,
    from arguments: [String: Any]
  ) throws -> [String: Any] {
    guard let value = arguments[key] as? [String: Any] else {
      throw MCPError("\(key) must be an object")
    }
    return value
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
        name: "list_captures",
        description: "Lists local Reframed screenshots and recording projects, newest first.",
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

private struct HTTPRequest {
  let method: String
  let target: String
  let headers: [String: String]
  let body: Data

  var path: String {
    URLComponents(string: "http://127.0.0.1\(target)")?.path ?? target
  }
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
