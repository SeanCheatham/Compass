import Darwin
import Foundation

enum GitRemoteCompassHelper {
  static let hostCID: UInt32 = 2
  static let gitServicePort: UInt32 = 0x4007_ACE6

  static func shouldRun(arguments: [String]) -> Bool {
    let executable = URL(fileURLWithPath: arguments.first ?? "").lastPathComponent
    if executable == "git-remote-compass" || arguments.contains("--git-remote-helper")
      || arguments.contains("--version")
    {
      return true
    }
    return arguments.dropFirst().contains { raw in
      raw.hasPrefix("compass::") || raw.hasPrefix("compass://")
    }
  }

  static func run(arguments: [String]) -> Never {
    if arguments.contains("--version") {
      writeString("git-remote-compass\n", to: STDOUT_FILENO)
      exit(0)
    }

    let repoID = parseRepoID(arguments: arguments)
    guard !repoID.isEmpty else {
      writeString("git-remote-compass: missing compass repo id\n", to: STDERR_FILENO)
      exit(2)
    }

    while true {
      guard let line = readLineFromFD(STDIN_FILENO, maxBytes: 8192) else {
        exit(0)
      }
      if line.isEmpty {
        exit(0)
      }
      if line == "capabilities" {
        writeString("connect\n\n", to: STDOUT_FILENO)
        continue
      }
      if line.hasPrefix("connect ") {
        let service = String(line.dropFirst("connect ".count))
        connect(repoID: repoID, service: service)
      }
      writeString("git-remote-compass: unsupported command \(line)\n", to: STDERR_FILENO)
      exit(2)
    }
  }

  private static func parseRepoID(arguments: [String]) -> String {
    let candidates = arguments.dropFirst().reversed()
    for raw in candidates {
      var value = raw
      if value.hasPrefix("compass::") {
        value = String(value.dropFirst("compass::".count))
      } else if value.hasPrefix("compass://") {
        value = String(value.dropFirst("compass://".count))
      }
      value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      if UUID(uuidString: value) != nil {
        return value.lowercased()
      }
    }
    return ""
  }

  private static func connect(repoID: String, service: String) -> Never {
    guard service == "git-upload-pack" || service == "git-receive-pack" else {
      writeString("git-remote-compass: unsupported service \(service)\n", to: STDERR_FILENO)
      exit(2)
    }
    let socketFD: Int32
    do {
      socketFD = try openHostSocket()
      try writeAll(Data("\(repoID) \(service)\n".utf8), to: socketFD)
      guard let response = readLineFromFD(socketFD, maxBytes: 4096) else {
        writeString("git-remote-compass: host git service closed during handshake\n", to: STDERR_FILENO)
        exit(2)
      }
      guard response == "ok" else {
        writeString("git-remote-compass: host git service rejected request: \(response)\n", to: STDERR_FILENO)
        exit(2)
      }
    } catch {
      writeString("git-remote-compass: \(error)\n", to: STDERR_FILENO)
      exit(2)
    }

    writeString("\n", to: STDOUT_FILENO)

    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      copyBytes(from: STDIN_FILENO, to: socketFD)
      _ = shutdown(socketFD, SHUT_WR)
      group.leave()
    }
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      copyBytes(from: socketFD, to: STDOUT_FILENO)
      group.leave()
    }
    group.wait()
    close(socketFD)
    exit(0)
  }

  private static func openHostSocket() throws -> Int32 {
    let fd = socket(VsockListener.AF_VSOCK, SOCK_STREAM, 0)
    guard fd >= 0 else { throw HelperError.socketFailed(errno) }
    var addr = sockaddr_vm()
    addr.svm_len = UInt8(MemoryLayout<sockaddr_vm>.size)
    addr.svm_family = sa_family_t(VsockListener.AF_VSOCK)
    addr.svm_port = gitServicePort
    addr.svm_cid = hostCID
    let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
        Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_vm>.size))
      }
    }
    if result != 0 {
      let error = errno
      close(fd)
      throw HelperError.connectFailed(error)
    }
    return fd
  }

  private enum HelperError: Error, CustomStringConvertible {
    case socketFailed(Int32)
    case connectFailed(Int32)
    case writeFailed(Int32)

    var description: String {
      switch self {
      case .socketFailed(let e): return "socket(AF_VSOCK) failed: \(String(cString: strerror(e)))"
      case .connectFailed(let e):
        return "connect(host git service) failed: \(String(cString: strerror(e)))"
      case .writeFailed(let e): return "write failed: \(String(cString: strerror(e)))"
      }
    }
  }

  private static func writeAll(_ data: Data, to fd: Int32) throws {
    try data.withUnsafeBytes { raw in
      var written = 0
      while written < data.count {
        guard let base = raw.baseAddress else { break }
        let count = Darwin.write(fd, base.advanced(by: written), data.count - written)
        if count < 0 {
          if errno == EINTR { continue }
          throw HelperError.writeFailed(errno)
        }
        if count == 0 { throw HelperError.writeFailed(EIO) }
        written += count
      }
    }
  }
}

private func readLineFromFD(_ fd: Int32, maxBytes: Int) -> String? {
  var data = Data()
  var byte: UInt8 = 0
  while data.count < maxBytes {
    let count = Darwin.read(fd, &byte, 1)
    if count == 0 {
      return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }
    if count < 0 {
      if errno == EINTR { continue }
      return nil
    }
    if byte == 0x0a {
      return String(decoding: data, as: UTF8.self)
    }
    data.append(byte)
  }
  return String(decoding: data, as: UTF8.self)
}

private func writeString(_ text: String, to fd: Int32) {
  Data(text.utf8).withUnsafeBytes { raw in
    var written = 0
    while written < raw.count {
      guard let base = raw.baseAddress else { break }
      let count = Darwin.write(fd, base.advanced(by: written), raw.count - written)
      if count < 0 {
        if errno == EINTR { continue }
        return
      }
      if count == 0 { return }
      written += count
    }
  }
}

private func copyBytes(from inputFD: Int32, to outputFD: Int32) {
  var buffer = [UInt8](repeating: 0, count: 64 * 1024)
  while true {
    let count = buffer.withUnsafeMutableBufferPointer { raw in
      Darwin.read(inputFD, raw.baseAddress, raw.count)
    }
    if count == 0 { return }
    if count < 0 {
      if errno == EINTR { continue }
      return
    }
    var written = 0
    while written < count {
      let n = buffer.withUnsafeBufferPointer { raw in
        Darwin.write(outputFD, raw.baseAddress!.advanced(by: written), count - written)
      }
      if n < 0 {
        if errno == EINTR { continue }
        return
      }
      if n == 0 { return }
      written += n
    }
  }
}
