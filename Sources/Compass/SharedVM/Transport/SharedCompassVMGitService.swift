import Darwin
import Foundation
import Virtualization

final class SharedCompassVMGitService: NSObject {
  static let shared = SharedCompassVMGitService()

  private let lock = NSLock()
  private var repositories: [String: URL] = [:]
  private var activeSessions: [ObjectIdentifier: GitServiceSession] = [:]
  private let listener = VZVirtioSocketListener()
  private lazy var listenerDelegate = ListenerDelegate(service: self)

  override private init() {
    super.init()
    signal(SIGPIPE, SIG_IGN)
    listener.delegate = listenerDelegate
  }

  @MainActor
  func install(on machine: VZVirtualMachine) {
    guard let socketDevice = machine.socketDevices.first as? VZVirtioSocketDevice else { return }
    socketDevice.setSocketListener(listener, forPort: SharedCompassVMVsock.gitServicePort)
  }

  @MainActor
  func remove(from machine: VZVirtualMachine) {
    guard let socketDevice = machine.socketDevices.first as? VZVirtioSocketDevice else { return }
    socketDevice.removeSocketListener(forPort: SharedCompassVMVsock.gitServicePort)
  }

  func register(repoID: String, exchangeRepoURL: URL) {
    guard SharedCompassVMGitExchange.isValidRepoID(repoID) else { return }
    lock.lock()
    repositories[repoID] = exchangeRepoURL.standardizedFileURL
    lock.unlock()
  }

  private func exchangeRepoURL(for repoID: String) -> URL? {
    lock.lock()
    defer { lock.unlock() }
    return repositories[repoID]
  }

  private func retain(_ session: GitServiceSession) {
    lock.lock()
    activeSessions[ObjectIdentifier(session)] = session
    lock.unlock()
  }

  private func release(_ session: GitServiceSession) {
    lock.lock()
    activeSessions.removeValue(forKey: ObjectIdentifier(session))
    lock.unlock()
  }

  fileprivate func accept(_ connection: VZVirtioSocketConnection) -> Bool {
    let session = GitServiceSession(connection: connection, service: self)
    retain(session)
    session.start()
    return true
  }

  private final class ListenerDelegate: NSObject, VZVirtioSocketListenerDelegate {
    weak var service: SharedCompassVMGitService?

    init(service: SharedCompassVMGitService) {
      self.service = service
    }

    func listener(
      _ listener: VZVirtioSocketListener,
      shouldAcceptNewConnection connection: VZVirtioSocketConnection,
      from socketDevice: VZVirtioSocketDevice
    ) -> Bool {
      service?.accept(connection) ?? false
    }
  }

  private final class GitServiceSession {
    private let connection: VZVirtioSocketConnection
    private weak var service: SharedCompassVMGitService?
    private let fd: Int32

    init(connection: VZVirtioSocketConnection, service: SharedCompassVMGitService) {
      self.connection = connection
      self.service = service
      fd = connection.fileDescriptor
    }

    func start() {
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        run()
        service?.release(self)
      }
    }

    private func run() {
      do {
        let header = try readLine(from: fd, maxBytes: 4096)
        let request = try GitServiceRequest.parse(header)
        guard let exchange = service?.exchangeRepoURL(for: request.repoID) else {
          try writeLine("error unknown repository\n", to: fd)
          return
        }
        try runGitService(request.service, exchangeRepoURL: exchange)
      } catch {
        try? writeLine("error \(String(describing: error))\n", to: fd)
      }
    }

    private func runGitService(_ serviceName: String, exchangeRepoURL: URL) throws {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      switch serviceName {
      case "git-upload-pack":
        process.arguments = ["upload-pack", "--strict", exchangeRepoURL.path]
      case "git-receive-pack":
        process.arguments = ["receive-pack", exchangeRepoURL.path]
      default:
        throw GitServiceError.unsupportedService(serviceName)
      }

      let stdin = Pipe()
      let stdout = Pipe()
      let stderr = Pipe()
      process.standardInput = stdin
      process.standardOutput = stdout
      process.standardError = stderr
      try process.run()
      try writeLine("ok\n", to: fd)

      let group = DispatchGroup()
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async { [fd] in
        Self.copyBytes(from: fd, to: stdin.fileHandleForWriting.fileDescriptor)
        try? stdin.fileHandleForWriting.close()
        group.leave()
      }

      group.enter()
      DispatchQueue.global(qos: .userInitiated).async { [fd] in
        Self.copyBytes(from: stdout.fileHandleForReading.fileDescriptor, to: fd)
        _ = shutdown(fd, SHUT_WR)
        group.leave()
      }

      process.waitUntilExit()
      _ = shutdown(fd, SHUT_RDWR)
      group.wait()

      let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
      if process.terminationStatus != 0, !stderrData.isEmpty {
        let text = String(decoding: stderrData, as: UTF8.self)
        FileHandle.standardError.write(Data("Compass git service failed: \(text)\n".utf8))
      }
    }

    private static func copyBytes(from inputFD: Int32, to outputFD: Int32) {
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
  }

  private struct GitServiceRequest {
    var repoID: String
    var service: String

    static func parse(_ header: String) throws -> GitServiceRequest {
      let parts = header.split(separator: " ", omittingEmptySubsequences: true)
      guard parts.count == 2 else { throw GitServiceError.invalidHeader(header) }
      let repoID = String(parts[0])
      let service = String(parts[1])
      guard SharedCompassVMGitExchange.isValidRepoID(repoID) else {
        throw GitServiceError.invalidRepository(repoID)
      }
      guard service == "git-upload-pack" || service == "git-receive-pack" else {
        throw GitServiceError.unsupportedService(service)
      }
      return GitServiceRequest(repoID: repoID, service: service)
    }
  }

  fileprivate enum GitServiceError: Error, CustomStringConvertible {
    case invalidHeader(String)
    case invalidRepository(String)
    case unsupportedService(String)
    case readFailed(Int32)
    case writeFailed(Int32)

    var description: String {
      switch self {
      case .invalidHeader(let header): return "invalid git service header: \(header)"
      case .invalidRepository(let repoID): return "invalid repository id: \(repoID)"
      case .unsupportedService(let service): return "unsupported git service: \(service)"
      case .readFailed(let errno):
        return "git service read failed: \(String(cString: strerror(errno)))"
      case .writeFailed(let errno):
        return "git service write failed: \(String(cString: strerror(errno)))"
      }
    }
  }
}

private func readLine(from fd: Int32, maxBytes: Int) throws -> String {
  var data = Data()
  data.reserveCapacity(min(maxBytes, 256))
  var byte: UInt8 = 0
  while data.count < maxBytes {
    let count = Darwin.read(fd, &byte, 1)
    if count == 0 { break }
    if count < 0 {
      if errno == EINTR { continue }
      throw SharedCompassVMGitService.GitServiceError.readFailed(errno)
    }
    if byte == 0x0a { break }
    data.append(byte)
  }
  return String(decoding: data, as: UTF8.self)
}

private func writeLine(_ line: String, to fd: Int32) throws {
  let data = Data(line.utf8)
  try data.withUnsafeBytes { raw in
    var written = 0
    while written < data.count {
      guard let base = raw.baseAddress else { break }
      let count = Darwin.write(fd, base.advanced(by: written), data.count - written)
      if count < 0 {
        if errno == EINTR { continue }
        throw SharedCompassVMGitService.GitServiceError.writeFailed(errno)
      }
      if count == 0 { throw SharedCompassVMGitService.GitServiceError.writeFailed(EIO) }
      written += count
    }
  }
}
