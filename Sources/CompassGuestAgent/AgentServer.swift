import CompassAgentRPC
import Darwin
import Foundation

/// One request → one response over an accepted vsock socket. The host opens
/// a fresh connection per RPC, so this code reads a single frame, dispatches
/// it, and writes a single response frame before closing the fd.
enum AgentServer {

  static func handleConnection(fileDescriptor fd: Int32) {
    defer { close(fd) }

    let request: AgentRPCRequest
    do {
      request = try AgentRPCFraming.readFrame(AgentRPCRequest.self) { wanted in
        try readBytes(from: fd, wanted: wanted)
      }
    } catch {
      // Attempt to write back a structured error before bailing — the
      // host can then surface a clean message instead of a transport
      // failure. If the write itself fails, the host will see the
      // socket close and infer a transport-level problem.
      let response = AgentRPCResponse.error(
        AgentRPCResponse.Error(
          kind: .invalidArguments,
          detail: "frame decode failed: \(error)"
        )
      )
      _ = try? writeResponse(response, to: fd)
      return
    }

    let response = dispatch(request)
    do {
      try writeResponse(response, to: fd)
    } catch {
      // Best-effort log to stderr; the host already sees the broken
      // connection and will retry.
      FileHandle.standardError.write(Data("compass-guest-agent: write failed: \(error)\n".utf8))
    }
  }

  /// Routes the request to the appropriate file-op and packages the result.
  /// Errors come back as `.error(...)` so the wire always carries a
  /// structured response, never a transport-level failure for app errors.
  static func dispatch(_ request: AgentRPCRequest) -> AgentRPCResponse {
    switch request {
    case .readFile(let args):
      switch AgentFileOperations.readFile(at: args.path) {
      case .success(let payload): return .readFile(payload)
      case .failure(let error): return .error(error)
      }
    case .writeFile(let args):
      switch AgentFileOperations.writeFile(at: args.path, dataBase64: args.dataBase64) {
      case .success: return .writeFile
      case .failure(let error): return .error(error)
      }
    case .stat(let args):
      switch AgentFileOperations.stat(at: args.path) {
      case .success(let payload): return .stat(payload)
      case .failure(let error): return .error(error)
      }
    case .listDirectory(let args):
      switch AgentFileOperations.listDirectory(at: args.path) {
      case .success(let payload): return .listDirectory(payload)
      case .failure(let error): return .error(error)
      }
    case .glob(let args):
      switch AgentFileOperations.glob(
        pattern: args.pattern, rootPath: args.rootPath, walkCap: args.walkCap)
      {
      case .success(let payload): return .glob(payload)
      case .failure(let error): return .error(error)
      }
    case .grep(let args):
      let result = AgentFileOperations.grep(
        pattern: args.pattern,
        path: args.path,
        glob: args.glob,
        caseInsensitive: args.caseInsensitive,
        timeoutSeconds: args.timeoutSeconds
      )
      return .grep(result)
    case .bash(let args):
      let result = AgentFileOperations.bash(
        command: args.command,
        workingDirectory: args.workingDirectory,
        timeoutSeconds: args.timeoutSeconds
      )
      return .bash(result)
    }
  }

  // MARK: - IO helpers

  private static func writeResponse(_ response: AgentRPCResponse, to fd: Int32) throws {
    let frame = try AgentRPCFraming.encode(response)
    try frame.withUnsafeBytes { raw in
      var written = 0
      while written < frame.count {
        guard let base = raw.baseAddress else { break }
        let n = Darwin.write(fd, base.advanced(by: written), frame.count - written)
        if n < 0 {
          if errno == EINTR { continue }
          throw IOError.writeFailed(errno: errno)
        }
        if n == 0 {
          throw IOError.writeFailed(errno: EIO)
        }
        written += n
      }
    }
  }

  private static func readBytes(from fd: Int32, wanted: Int) throws -> Data? {
    var buffer = [UInt8](repeating: 0, count: wanted)
    var totalRead = 0
    while totalRead == 0 {
      let n = buffer.withUnsafeMutableBufferPointer { buf -> Int in
        Darwin.read(fd, buf.baseAddress, wanted)
      }
      if n < 0 {
        if errno == EINTR { continue }
        throw IOError.readFailed(errno: errno)
      }
      if n == 0 {
        // EOF before any bytes — caller treats this as closed.
        return nil
      }
      totalRead = n
    }
    return Data(buffer.prefix(totalRead))
  }

  enum IOError: Error, CustomStringConvertible {
    case readFailed(errno: Int32)
    case writeFailed(errno: Int32)

    var description: String {
      switch self {
      case .readFailed(let e): return "read failed: \(String(cString: strerror(e)))"
      case .writeFailed(let e): return "write failed: \(String(cString: strerror(e)))"
      }
    }
  }
}
