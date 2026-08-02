import CompassAgentRPC
import Foundation

/// Host-side client for the in-guest Compass agent. Implements both
/// `AgentFilesystem` and `AgentBashRunner` over a length-prefixed JSON
/// RPC carried by vsock — one request per connection, one response, then
/// close. The transport is injected so unit tests can stub it without
/// spinning up a real VM.
///
/// All op-level errors (notFound / notRegularFile / etc.) are translated
/// from the wire's `AgentRPCResponse.Error` into Compass's local
/// `AgentFilesystemError` so tools above this layer don't have to know
/// about the wire vocabulary.
public struct AgentVsockClient: AgentFilesystem, AgentBashRunner {
  public let transportFactory: VsockTransportFactory
  public let requestTimeout: TimeInterval

  public init(
    transportFactory: @escaping VsockTransportFactory,
    requestTimeout: TimeInterval = 120
  ) {
    self.transportFactory = transportFactory
    self.requestTimeout = requestTimeout
  }

  // MARK: - AgentFilesystem

  public func readFile(at url: URL) async throws -> Data {
    let response = try await roundTrip(.readFile(.init(path: url.path)))
    switch response {
    case .readFile(let result):
      guard let data = Data(base64Encoded: result.dataBase64) else {
        throw AgentFilesystemError.ioFailure("readFile: malformed base64 response for \(url.path)")
      }
      return data
    case .error(let error):
      throw Self.mapError(error, defaultURL: url)
    default:
      throw AgentFilesystemError.transportFailure("readFile: unexpected response \(response)")
    }
  }

  public func writeFile(_ data: Data, at url: URL) async throws {
    let response = try await roundTrip(
      .writeFile(.init(path: url.path, dataBase64: data.base64EncodedString())))
    switch response {
    case .writeFile:
      return
    case .error(let error):
      throw Self.mapError(error, defaultURL: url)
    default:
      throw AgentFilesystemError.transportFailure("writeFile: unexpected response \(response)")
    }
  }

  public func metadata(of url: URL) async throws -> FileMetadata? {
    let response = try await roundTrip(.stat(.init(path: url.path)))
    switch response {
    case .stat(let result):
      guard let m = result.metadata else { return nil }
      return FileMetadata(
        url: URL(fileURLWithPath: m.path),
        isDirectory: m.isDirectory,
        isRegularFile: m.isRegularFile,
        size: m.size,
        modificationDate: m.modificationDateEpoch.map { Date(timeIntervalSince1970: $0) }
      )
    case .error(let error):
      throw Self.mapError(error, defaultURL: url)
    default:
      throw AgentFilesystemError.transportFailure("stat: unexpected response \(response)")
    }
  }

  public func listDirectory(at url: URL) async throws -> [DirectoryEntry] {
    let response = try await roundTrip(.listDirectory(.init(path: url.path)))
    switch response {
    case .listDirectory(let result):
      return result.entries.map { wire in
        DirectoryEntry(
          url: URL(fileURLWithPath: wire.path),
          name: wire.name,
          isDirectory: wire.isDirectory
        )
      }
    case .error(let error):
      throw Self.mapError(error, defaultURL: url)
    default:
      throw AgentFilesystemError.transportFailure("listDirectory: unexpected response \(response)")
    }
  }

  public func glob(pattern: String, under rootURL: URL, walkCap: Int) async throws -> [GlobMatch] {
    let response = try await roundTrip(
      .glob(.init(pattern: pattern, rootPath: rootURL.path, walkCap: walkCap)))
    switch response {
    case .glob(let result):
      return result.matches.map { wire in
        GlobMatch(
          url: URL(fileURLWithPath: wire.path),
          modificationDate: wire.modificationDateEpoch.map { Date(timeIntervalSince1970: $0) }
        )
      }
    case .error(let error):
      throw Self.mapError(error, defaultURL: rootURL)
    default:
      throw AgentFilesystemError.transportFailure("glob: unexpected response \(response)")
    }
  }

  public func grep(
    pattern: String,
    in url: URL,
    glob: String?,
    caseInsensitive: Bool,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    let response = try await roundTrip(
      .grep(
        .init(
          pattern: pattern,
          path: url.path,
          glob: glob,
          caseInsensitive: caseInsensitive,
          timeoutSeconds: timeout
        )),
      watchdogTimeout: effectiveWatchdogTimeout(forCommandTimeout: timeout)
    )
    switch response {
    case .grep(let result):
      return ProcessResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
    case .error(let error):
      throw Self.mapError(error, defaultURL: url)
    default:
      throw AgentFilesystemError.transportFailure("grep: unexpected response \(response)")
    }
  }

  // MARK: - AgentBashRunner

  public func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    let response = try await roundTrip(
      .bash(
        .init(
          command: command,
          workingDirectory: workingDirectory.path,
          timeoutSeconds: timeout
        )),
      watchdogTimeout: effectiveWatchdogTimeout(forCommandTimeout: timeout)
    )
    switch response {
    case .bash(let result):
      return ProcessResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
    case .error(let error):
      // Bash errors come back as ProcessResult, not RPC errors — but
      // an RPC-level error here means the transport itself broke.
      throw AgentRPCTransportError.guestReportedError(error)
    default:
      throw AgentFilesystemError.transportFailure("bash: unexpected response \(response)")
    }
  }

  // MARK: - Wire round trip

  /// The host-side watchdog must never fire before the guest-side command
  /// has had a chance to finish on its own clock: long builds (`swift build`,
  /// `cargo test`) legitimately run far longer than the default 120s
  /// `requestTimeout`. Scale the watchdog to the command timeout plus a
  /// transport margin so the guest always gets to report its own timeout
  /// (exit code 124) first.
  static let watchdogMarginSeconds: TimeInterval = 30

  public func effectiveWatchdogTimeout(forCommandTimeout commandTimeout: TimeInterval)
    -> TimeInterval
  {
    max(requestTimeout, commandTimeout + Self.watchdogMarginSeconds)
  }

  private func roundTrip(
    _ request: AgentRPCRequest,
    watchdogTimeout: TimeInterval? = nil
  ) async throws -> AgentRPCResponse {
    let watchdog = watchdogTimeout ?? requestTimeout
    let transportHolder = VsockTransportHolder()
    return try await withThrowingTaskGroup(of: AgentRPCResponse.self) { group in
      group.addTask {
        try await self.performRoundTrip(request, transportHolder: transportHolder)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(watchdog * 1_000_000_000))
        await transportHolder.close()
        throw AgentFilesystemError.transportFailure(
          "vsock request timed out after \(Int(watchdog))s")
      }
      guard let response = try await group.next() else {
        throw AgentFilesystemError.transportFailure("vsock request failed")
      }
      group.cancelAll()
      return response
    }
  }

  private func performRoundTrip(
    _ request: AgentRPCRequest,
    transportHolder: VsockTransportHolder
  ) async throws -> AgentRPCResponse {
    let transport: VsockTransport
    do {
      transport = try await transportFactory()
    } catch {
      throw AgentFilesystemError.transportFailure(
        "vsock connect failed: \(error.localizedDescription)")
    }
    await transportHolder.set(transport)
    defer { Task { await transport.close() } }

    let frame: Data
    do {
      frame = try AgentRPCFraming.encode(request)
    } catch {
      throw AgentFilesystemError.ioFailure("vsock encode failed: \(error.localizedDescription)")
    }

    do {
      try await transport.write(frame)
    } catch {
      throw AgentFilesystemError.transportFailure(
        "vsock write failed: \(error.localizedDescription)")
    }

    // The agent closes its end after writing the response, so EOF
    // marks the natural end of the frame. Drain everything, then
    // decode in one shot — bounded by `maxFrameByteCount + 4` so a
    // misbehaving remote can't exhaust host memory.
    do {
      let buffer = try await readUntilEOF(
        from: transport, maxBytes: AgentRPCFraming.maxFrameByteCount + 4)
      return try AgentRPCFraming.decode(AgentRPCResponse.self, from: buffer)
    } catch let error as AgentRPCFraming.FramingError {
      throw AgentFilesystemError.transportFailure("vsock decode failed: \(error)")
    } catch {
      throw AgentFilesystemError.transportFailure(
        "vsock read failed: \(error.localizedDescription)")
    }
  }

  /// Drain the transport until the remote closes. Used for one-shot
  /// connections (one request, one response, close). Bounded so a
  /// misbehaving remote can't exhaust host memory.
  private func readUntilEOF(from transport: VsockTransport, maxBytes: Int) async throws -> Data {
    var buffer = Data()
    let chunkSize = 64 * 1024
    while buffer.count < maxBytes {
      guard let chunk = try await transport.read(wanted: chunkSize) else { break }
      if chunk.isEmpty { break }
      buffer.append(chunk)
    }
    return buffer
  }

  private static func mapError(_ error: AgentRPCResponse.Error, defaultURL: URL)
    -> AgentFilesystemError
  {
    switch error.kind {
    case .notFound: return .notFound(defaultURL)
    case .notRegularFile: return .notRegularFile(defaultURL)
    case .notDirectory: return .notDirectory(defaultURL)
    case .ioFailure: return .ioFailure(error.detail)
    case .invalidArguments: return .ioFailure("invalid arguments: \(error.detail)")
    case .internalError: return .transportFailure("guest internal error: \(error.detail)")
    }
  }
}

/// Transport abstraction the vsock client speaks to. The production
/// implementation wraps `VZVirtioSocketConnection`; tests inject a
/// memory-backed stub.
public protocol VsockTransport: Sendable {
  /// Write all of `data` to the connection. Throws on partial write
  /// or transport-level failure.
  func write(_ data: Data) async throws

  /// Read up to `wanted` bytes. Returns nil for EOF (remote closed).
  func read(wanted: Int) async throws -> Data?

  /// Close the connection. Idempotent.
  func close() async
}

/// Factory closure used by `AgentVsockClient` to open a fresh transport
/// per request. One request, one response, then close — keeps the protocol
/// stateless on the wire.
public typealias VsockTransportFactory = @Sendable () async throws -> any VsockTransport

/// Holds the live transport so a watchdog task can close it when
/// `requestTimeout` fires, unblocking a stuck read.
private actor VsockTransportHolder {
  private var transport: (any VsockTransport)?

  func set(_ transport: any VsockTransport) {
    self.transport = transport
  }

  func close() async {
    if let transport {
      await transport.close()
    }
    self.transport = nil
  }
}

public enum AgentRPCTransportError: Error, CustomStringConvertible {
  case guestReportedError(AgentRPCResponse.Error)

  public var description: String {
    switch self {
    case .guestReportedError(let error):
      return "guest agent reported error: \(error.kind.rawValue): \(error.detail)"
    }
  }
}
