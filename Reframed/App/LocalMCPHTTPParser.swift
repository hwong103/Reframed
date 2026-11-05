import Foundation

struct LocalMCPHTTPRequest: Sendable {
  let method: String
  let target: String
  let headers: [String: String]
  let body: Data

  var path: String {
    URLComponents(string: "http://127.0.0.1\(target)")?.path ?? target
  }
}

struct LocalMCPHTTPParseError: Error, Equatable {
  let status: Int
  let message: String
}

enum LocalMCPHTTPParser {
  static let maxHeaderBytes = 64 * 1024
  static let maxRequestBodyBytes = 8 * 1024 * 1024
  static let maxBufferedRequestBytes = maxHeaderBytes + maxRequestBodyBytes

  static func parse(
    _ buffer: Data
  ) -> Result<LocalMCPHTTPRequest?, LocalMCPHTTPParseError> {
    let delimiter = Data("\r\n\r\n".utf8)
    guard let headerRange = buffer.range(of: delimiter) else {
      return .success(nil)
    }
    guard headerRange.upperBound <= maxHeaderBytes else {
      return .failure(
        LocalMCPHTTPParseError(status: 413, message: "HTTP headers are too large")
      )
    }

    let headerData = buffer[..<headerRange.lowerBound]
    guard let headerText = String(data: headerData, encoding: .utf8) else {
      return .failure(
        LocalMCPHTTPParseError(status: 400, message: "HTTP headers must be UTF-8")
      )
    }
    let lines = headerText.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else {
      return .failure(
        LocalMCPHTTPParseError(status: 400, message: "Missing HTTP request line")
      )
    }
    let requestParts = requestLine.split(separator: " ")
    guard requestParts.count >= 2 else {
      return .failure(
        LocalMCPHTTPParseError(status: 400, message: "Invalid HTTP request line")
      )
    }

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let separator = line.firstIndex(of: ":") else {
        return .failure(
          LocalMCPHTTPParseError(status: 400, message: "Invalid HTTP header")
        )
      }
      let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
      guard !key.isEmpty else {
        return .failure(
          LocalMCPHTTPParseError(status: 400, message: "Invalid empty HTTP header name")
        )
      }
      let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      headers[key] = value
    }

    let contentLength: Int
    if let rawLength = headers["content-length"] {
      guard !rawLength.isEmpty,
        rawLength.allSatisfy(\.isNumber),
        let parsedLength = Int(rawLength)
      else {
        return .failure(
          LocalMCPHTTPParseError(
            status: 400,
            message: "Content-Length must be a non-negative integer"
          )
        )
      }
      contentLength = parsedLength
    } else {
      contentLength = 0
    }
    guard contentLength <= maxRequestBodyBytes else {
      return .failure(
        LocalMCPHTTPParseError(status: 413, message: "Request body is too large")
      )
    }

    let bodyStart = headerRange.upperBound
    guard buffer.count >= bodyStart + contentLength else { return .success(nil) }
    let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
    return .success(
      LocalMCPHTTPRequest(
        method: String(requestParts[0]),
        target: String(requestParts[1]),
        headers: headers,
        body: body
      )
    )
  }
}
