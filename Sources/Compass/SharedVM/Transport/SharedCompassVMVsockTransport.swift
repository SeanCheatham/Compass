import Darwin
import Foundation
import Virtualization

/// `VsockTransport` backed by a live `VZVirtioSocketConnection`. The
/// connection's file descriptor is a regular POSIX socket fd; we read/write
/// on it directly with `Darwin.read`/`Darwin.write`. Reads block, so the
/// async helpers hop to a detached task — we don't want to stall the
/// caller's actor on a slow remote.
///
/// The `VZVirtioSocketConnection` itself must stay alive for the duration
/// of the connection (deinit closes the underlying socket). We retain it
/// for as long as this transport exists.
final class VZVirtioSocketTransport: VsockTransport, @unchecked Sendable {
  private let connection: VZVirtioSocketConnection
  private let fileDescriptor: Int32
  private let closedLock = NSLock()
  private var closed = false

  init(connection: VZVirtioSocketConnection) {
    self.connection = connection
    self.fileDescriptor = connection.fileDescriptor
  }

  deinit {
    // Capture `fileDescriptor` (a value type) directly — DO NOT spawn
    // a `Task { [self] in close() }`. By the time such a task runs,
    // `self`'s refcount has already dropped to zero and the deinit is
    // tearing the instance down; the ObjC runtime trying to retain
    // a half-deallocated instance crashes with EXC_BAD_ACCESS in
    // objc_retain. Closing the fd is the only cleanup needed, and
    // it's fd-local — no need to touch `self` at all in deinit.
    closedLock.lock()
    let needsClose = !closed
    closed = true
    closedLock.unlock()
    if needsClose {
      Darwin.close(fileDescriptor)
    }
  }

  func write(_ data: Data) async throws {
    try await Task.detached { [self] in
      try data.withUnsafeBytes { raw in
        var written = 0
        while written < data.count {
          guard let base = raw.baseAddress else { break }
          let n = Darwin.write(fileDescriptor, base.advanced(by: written), data.count - written)
          if n < 0 {
            if errno == EINTR { continue }
            throw IOError.writeFailed(errno: errno)
          }
          if n == 0 { throw IOError.writeFailed(errno: EIO) }
          written += n
        }
      }
    }.value
  }

  func read(wanted: Int) async throws -> Data? {
    try await Task.detached { [self] in
      var buffer = [UInt8](repeating: 0, count: wanted)
      while true {
        let n = buffer.withUnsafeMutableBufferPointer { buf -> Int in
          Darwin.read(fileDescriptor, buf.baseAddress, wanted)
        }
        if n < 0 {
          if errno == EINTR { continue }
          throw IOError.readFailed(errno: errno)
        }
        if n == 0 { return nil as Data? }
        return Data(buffer.prefix(n)) as Data?
      }
    }.value
  }

  func close() async {
    guard claimCloseToken() else { return }
    // VZVirtioSocketConnection's docs say closing the fd shuts down
    // the channel; the VZ object itself is reference-counted and
    // releases when the last reference drops.
    Darwin.close(fileDescriptor)
  }

  /// Synchronous lock/unlock pair — Swift 6 disallows NSLock.lock/unlock
  /// across async suspension points, so the actual mutation is funneled
  /// through this sync helper that the async `close()` calls.
  private func claimCloseToken() -> Bool {
    closedLock.lock()
    defer { closedLock.unlock() }
    guard !closed else { return false }
    closed = true
    return true
  }

  enum IOError: Error, CustomStringConvertible {
    case readFailed(errno: Int32)
    case writeFailed(errno: Int32)

    var description: String {
      switch self {
      case .readFailed(let e): return "vsock read failed: \(String(cString: strerror(e)))"
      case .writeFailed(let e): return "vsock write failed: \(String(cString: strerror(e)))"
      }
    }
  }
}
