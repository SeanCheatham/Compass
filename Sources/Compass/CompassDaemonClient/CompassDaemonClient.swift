import Darwin
import Foundation

enum CompassDaemonClientError: Error, LocalizedError {
  case pathTooLong(String)
  case connectFailed(String)
  case writeFailed(String)
  case readFailed(String)
  case emptyResponse
  case daemonRejected([String])

  var errorDescription: String? {
    switch self {
    case .pathTooLong(let path):
      "Socket path is too long for Unix domain sockets: \(path)"
    case .connectFailed(let message):
      "Could not connect to compassd: \(message)"
    case .writeFailed(let message):
      "Could not write to compassd: \(message)"
    case .readFailed(let message):
      "Could not read from compassd: \(message)"
    case .emptyResponse:
      "compassd returned an empty response"
    case .daemonRejected(let errors):
      errors.joined(separator: "\n")
    }
  }
}

final class CompassDaemonClient {
  let socketURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(socketURL: URL) {
    self.socketURL = socketURL
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
  }

  func ping() async throws -> CompassDaemonPing {
    try await send(method: "ping", resultType: CompassDaemonPing.self)
  }

  func capabilities() async throws -> CompassDaemonCapabilities {
    try await send(method: "get_capabilities", resultType: CompassDaemonCapabilities.self)
  }

  func shutdown() async throws {
    _ = try await send(method: "shutdown", resultType: CompassDaemonEmptyResult.self)
      as CompassDaemonEmptyResult
  }

  func send<Result: Decodable>(
    method: String,
    params: [String: String] = [:],
    resultType: Result.Type
  ) async throws -> Result {
    let request = CompassDaemonRequest(id: UUID().uuidString, method: method, params: params)
    var data = try encoder.encode(request)
    data.append(0x0A)
    let socketPath = socketURL.path
    let responseData = try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          continuation.resume(returning: try Self.roundTrip(socketPath: socketPath, data: data))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
    let response = try decoder.decode(CompassDaemonResponse<Result>.self, from: responseData)
    guard response.ok else {
      throw CompassDaemonClientError.daemonRejected(response.errors)
    }
    guard let result = response.result else {
      throw CompassDaemonClientError.emptyResponse
    }
    return result
  }

  private static func roundTrip(socketPath: String, data: Data) throws -> Data {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw CompassDaemonClientError.connectFailed(String(cString: strerror(errno)))
    }
    defer { close(fd) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
    guard socketPath.utf8.count < maxPathLength else {
      throw CompassDaemonClientError.pathTooLong(socketPath)
    }
    socketPath.withCString { pointer in
      withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: UnsafeRawBufferPointer(start: pointer, count: strlen(pointer) + 1))
      }
    }

    let connected = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else {
      throw CompassDaemonClientError.connectFailed(String(cString: strerror(errno)))
    }

    try data.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else { return }
      var written = 0
      while written < rawBuffer.count {
        let count = Darwin.write(fd, base.advanced(by: written), rawBuffer.count - written)
        guard count > 0 else {
          throw CompassDaemonClientError.writeFailed(String(cString: strerror(errno)))
        }
        written += count
      }
    }

    var response = Data()
    var byte: UInt8 = 0
    while true {
      let count = Darwin.read(fd, &byte, 1)
      guard count > 0 else {
        if response.isEmpty {
          throw CompassDaemonClientError.readFailed(String(cString: strerror(errno)))
        }
        break
      }
      if byte == 0x0A { break }
      response.append(byte)
    }
    return response
  }
}
