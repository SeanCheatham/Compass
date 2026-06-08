import Darwin
import Foundation
import Testing

@testable import Compass

struct CompassDaemonClientTests {
  @Test func daemonLocatorFindsDevBinary() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "CompassDaemonLocatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let binary = root
      .appending(path: "target", directoryHint: .isDirectory)
      .appending(path: "debug", directoryHint: .isDirectory)
      .appending(path: "compassd")
    try FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "#!/bin/sh\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

    let original = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(root.path)
    defer { FileManager.default.changeCurrentDirectoryPath(original) }

    #expect(CompassDaemonLocator.locateDaemonBinary()?.path == binary.path)
  }

  @Test func clientPingsTestSocket() async throws {
    let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appending(path: "cdct-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let socketURL = root.appending(path: "daemon.sock")
    let server = try TestDaemonServer(socketURL: socketURL)
    defer { server.stop() }

    let client = CompassDaemonClient(socketURL: socketURL)
    let ping = try await client.ping()

    #expect(ping.compassdVersion == "test-daemon")
    #expect(ping.coreVersion == "test-core")
    #expect(ping.schemaVersion == 1)
  }
}

private final class TestDaemonServer {
  private let fd: Int32
  private let queue = DispatchQueue(label: "CompassDaemonClientTests.server")
  private var isStopped = false

  init(socketURL: URL) throws {
    fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    guard socketURL.path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
      throw POSIXError(.ENAMETOOLONG)
    }
    socketURL.path.withCString { pointer in
      withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: UnsafeRawBufferPointer(start: pointer, count: strlen(pointer) + 1))
      }
    }

    let didBind = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard didBind == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard listen(fd, 1) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    queue.async { [weak self] in
      self?.acceptOne()
    }
  }

  func stop() {
    isStopped = true
    close(fd)
  }

  private func acceptOne() {
    let client = accept(fd, nil, nil)
    guard client >= 0, !isStopped else { return }
    defer { close(client) }

    var line = Data()
    var byte: UInt8 = 0
    while Darwin.read(client, &byte, 1) > 0 {
      if byte == 0x0A { break }
      line.append(byte)
    }
    let response = """
      {"schema_version":1,"id":"test","ok":true,"result":{"compassdVersion":"test-daemon","coreVersion":"test-core","schemaVersion":1},"errors":[]}
      """
    let data = Data((response + "\n").utf8)
    data.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else { return }
      _ = Darwin.write(client, base, rawBuffer.count)
    }
  }
}
