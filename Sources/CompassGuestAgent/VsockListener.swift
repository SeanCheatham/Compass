// swift-format-ignore-file: AlwaysUseLowerCamelCase, TypeNamesShouldBeCapitalized
// The naming exceptions mirror the C ABI from <sys/vsock.h> so the Swift
// declarations stay readable next to the kernel headers.

import Darwin
import Foundation

/// Listens on AF_VSOCK at a fixed port and yields each accepted connection
/// to a handler. AF_VSOCK is a Darwin-supported socket family for VM-host
/// communication that bypasses the network stack entirely; on the macOS
/// guest, it's the one transport that isn't subject to the VirtioFS-mount
/// TCC restrictions blocking sshd.
///
/// `mount_virtiofs`-mounted shares + sshd_spawned processes return EPERM
/// for any access. Processes spawned from the user GUI session (e.g.
/// Terminal.app, or LaunchAgents loaded into the session) bypass that
/// check — the guest agent is loaded as a LaunchAgent so it inherits the
/// right TCC profile for accessing the VirtioFS-mounted worktree.
final class VsockListener {
  /// macOS AF_VSOCK socket family (defined in <sys/socket.h>).
  static let AF_VSOCK: Int32 = 40

  /// Wildcard CID — bind to "any CID" so the listen socket accepts
  /// connections from the host (CID 2 on guests) without us caring.
  static let VMADDR_CID_ANY: UInt32 = 0xFFFF_FFFF

  enum ListenerError: Error, CustomStringConvertible {
    case socketFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
    case acceptFailed(errno: Int32)

    var description: String {
      switch self {
      case .socketFailed(let e): return "socket(AF_VSOCK) failed: \(String(cString: strerror(e)))"
      case .bindFailed(let e): return "bind failed: \(String(cString: strerror(e)))"
      case .listenFailed(let e): return "listen failed: \(String(cString: strerror(e)))"
      case .acceptFailed(let e): return "accept failed: \(String(cString: strerror(e)))"
      }
    }
  }

  private let port: UInt32
  private var listenSocket: Int32 = -1

  init(port: UInt32) {
    self.port = port
  }

  deinit {
    if listenSocket >= 0 { close(listenSocket) }
  }

  /// Bind + listen on the configured port.
  func start(backlog: Int32 = 16) throws {
    let fd = socket(VsockListener.AF_VSOCK, SOCK_STREAM, 0)
    if fd < 0 {
      throw ListenerError.socketFailed(errno: errno)
    }

    // Build sockaddr_vm with C struct layout — Darwin doesn't expose a
    // Swift binding for this struct.
    var addr = sockaddr_vm()
    addr.svm_len = UInt8(MemoryLayout<sockaddr_vm>.size)
    addr.svm_family = sa_family_t(VsockListener.AF_VSOCK)
    addr.svm_port = port
    addr.svm_cid = VsockListener.VMADDR_CID_ANY

    let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
        bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_vm>.size))
      }
    }
    if bindResult < 0 {
      let e = errno
      close(fd)
      throw ListenerError.bindFailed(errno: e)
    }

    if listen(fd, backlog) < 0 {
      let e = errno
      close(fd)
      throw ListenerError.listenFailed(errno: e)
    }

    listenSocket = fd
  }

  /// Block-accept loop. Calls `handle` synchronously per connection; the
  /// handler owns the returned file descriptor (closes it when done).
  func acceptLoop(_ handle: (Int32) -> Void) throws {
    while true {
      let client = accept(listenSocket, nil, nil)
      if client < 0 {
        // EINTR is a transient signal interruption; retry.
        if errno == EINTR { continue }
        throw ListenerError.acceptFailed(errno: errno)
      }
      handle(client)
    }
  }
}

/// Minimal sockaddr_vm shim. macOS doesn't ship a Swift binding for this
/// struct; we lay it out matching the kernel's `<sys/vsock.h>` definition.
/// Field order and sizes match the C struct exactly so a cast from
/// `sockaddr` to `sockaddr_vm` works.
struct sockaddr_vm {
  var svm_len: UInt8 = 0
  var svm_family: sa_family_t = 0
  var svm_reserved1: UInt16 = 0
  var svm_port: UInt32 = 0
  var svm_cid: UInt32 = 0
  var svm_zero: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
}
