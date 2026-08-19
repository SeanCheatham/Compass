import CompassAgentRPC
import Darwin
import Foundation

/// posix_spawn wrapper used by the guest agent for bash/grep.
///
/// `Foundation.Process` is unsafe here: the agent is a LaunchDaemon that
/// accepts vsock RPCs concurrently, and Process/FileHandle close stdin and
/// pipe fds after spawn. Those numeric fds get reused by `accept()`, then
/// the next `posix_spawn` (or a FileHandle deinit) hits EBADF — Studio
/// surfaces that as `failed to launch /bin/zsh: Bad file descriptor`.
///
/// This runner never uses FileHandle. Stdin is `/dev/null` via a spawn
/// file action; stdout/stderr are raw pipes; extra fds are dropped with
/// `POSIX_SPAWN_CLOEXEC_DEFAULT`.
enum GuestProcess {
  private static let processLock = NSLock()

  static func run(
    executable: String,
    arguments: [String],
    workingDirectory: String?,
    environment: [String: String],
    timeoutSeconds: Double
  ) -> AgentRPCResponse.ProcessResult {
    processLock.lock()
    defer { processLock.unlock() }

    guard let stdout = makePipe(), let stderr = makePipe() else {
      return launchFailure(executable, errno: errno)
    }
    var stdoutRead = stdout.read
    var stdoutWrite = stdout.write
    var stderrRead = stderr.read
    var stderrWrite = stderr.write
    defer {
      closeFd(&stdoutRead)
      closeFd(&stdoutWrite)
      closeFd(&stderrRead)
      closeFd(&stderrWrite)
    }

    var fileActions: posix_spawn_file_actions_t?
    var initRc = posix_spawn_file_actions_init(&fileActions)
    guard initRc == 0 else { return launchFailure(executable, errno: initRc) }
    defer { posix_spawn_file_actions_destroy(&fileActions) }

    let openStdin = "/dev/null".withCString { path in
      posix_spawn_file_actions_addopen(
        &fileActions, STDIN_FILENO, path, O_RDONLY, 0)
    }
    guard openStdin == 0 else { return launchFailure(executable, errno: openStdin) }
    let dupOut = posix_spawn_file_actions_adddup2(
      &fileActions, stdoutWrite, STDOUT_FILENO)
    guard dupOut == 0 else { return launchFailure(executable, errno: dupOut) }
    let dupErr = posix_spawn_file_actions_adddup2(
      &fileActions, stderrWrite, STDERR_FILENO)
    guard dupErr == 0 else { return launchFailure(executable, errno: dupErr) }

    if let workingDirectory {
      let chdirRc = workingDirectory.withCString { path in
        posix_spawn_file_actions_addchdir(&fileActions, path)
      }
      guard chdirRc == 0 else { return launchFailure(executable, errno: chdirRc) }
    }

    var attr: posix_spawnattr_t?
    initRc = posix_spawnattr_init(&attr)
    guard initRc == 0 else { return launchFailure(executable, errno: initRc) }
    defer { posix_spawnattr_destroy(&attr) }

    let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
    posix_spawnattr_setflags(&attr, flags)
    posix_spawnattr_setpgroup(&attr, 0)

    let argv = [executable] + arguments
    let env = environment.map { "\($0.key)=\($0.value)" }
    var pid: pid_t = 0
    let spawnRc = withCStringArray(argv) { argvPtr in
      withCStringArray(env) { envPtr in
        executable.withCString { path in
          posix_spawn(&pid, path, &fileActions, &attr, argvPtr, envPtr)
        }
      }
    }
    if spawnRc != 0 {
      return launchFailure(executable, errno: spawnRc)
    }

    closeFd(&stdoutWrite)
    closeFd(&stderrWrite)

    let stdoutSink = DrainSink()
    let stderrSink = DrainSink()
    let drainGroup = DispatchGroup()
    let capturedStdout = stdoutRead
    let capturedStderr = stderrRead
    stdoutRead = -1
    stderrRead = -1
    drainGroup.enter()
    DispatchQueue.global(qos: .utility).async {
      stdoutSink.data = readAll(from: capturedStdout)
      _ = Darwin.close(capturedStdout)
      drainGroup.leave()
    }
    drainGroup.enter()
    DispatchQueue.global(qos: .utility).async {
      stderrSink.data = readAll(from: capturedStderr)
      _ = Darwin.close(capturedStderr)
      drainGroup.leave()
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    var status: Int32 = 0
    var timedOut = false
    while true {
      let waited = waitpid(pid, &status, WNOHANG)
      if waited == pid { break }
      if waited < 0 && errno != EINTR {
        timedOut = true
        break
      }
      if Date() >= deadline {
        timedOut = true
        break
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    // Always SIGKILL the process group: on timeout this reaps the child,
    // and on clean zsh exit it reaps backgrounded grandchildren that still
    // hold the pipe write ends (otherwise drain blocks on EOF forever).
    _ = kill(-pid, SIGKILL)
    if timedOut {
      _ = waitpid(pid, &status, 0)
    }

    drainGroup.wait()
    var stderrText = String(decoding: stderrSink.data, as: UTF8.self)
    if timedOut {
      if !stderrText.isEmpty && !stderrText.hasSuffix("\n") { stderrText += "\n" }
      stderrText += "[timed out after \(Int(timeoutSeconds * 1000)) ms]"
    }
    return AgentRPCResponse.ProcessResult(
      exitCode: decodeWaitStatus(status),
      stdout: String(decoding: stdoutSink.data, as: UTF8.self),
      stderr: stderrText
    )
  }

  private static func launchFailure(_ executable: String, errno: Int32)
    -> AgentRPCResponse.ProcessResult
  {
    let detail = String(cString: strerror(errno))
    return AgentRPCResponse.ProcessResult(
      exitCode: 127,
      stdout: "",
      stderr: "failed to launch \(executable): \(detail)"
    )
  }

  private static func makePipe() -> (read: Int32, write: Int32)? {
    var fds = [Int32](repeating: -1, count: 2)
    let rc = fds.withUnsafeMutableBufferPointer { Darwin.pipe($0.baseAddress!) }
    guard rc == 0 else { return nil }
    _ = fcntl(fds[0], F_SETFD, FD_CLOEXEC)
    _ = fcntl(fds[1], F_SETFD, FD_CLOEXEC)
    return (fds[0], fds[1])
  }

  private static func closeFd(_ fd: inout Int32) {
    if fd >= 0 {
      _ = Darwin.close(fd)
      fd = -1
    }
  }

  private static func readAll(from fd: Int32) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
      let n = buffer.withUnsafeMutableBytes { ptr in
        Darwin.read(fd, ptr.baseAddress, ptr.count)
      }
      if n < 0 {
        if errno == EINTR { continue }
        break
      }
      if n == 0 { break }
      data.append(contentsOf: buffer.prefix(Int(n)))
    }
    return data
  }

  private static func decodeWaitStatus(_ status: Int32) -> Int32 {
    let waitStatus = status & 0o177
    if waitStatus == 0 { return (status >> 8) & 0xff }
    if waitStatus != 0o177 { return 128 + waitStatus }
    return status
  }

  private static func withCStringArray<R>(
    _ strings: [String],
    _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R
  ) -> R {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer {
      for pointer in pointers { free(pointer) }
    }
    return pointers.withUnsafeBufferPointer { buffer in
      body(buffer.baseAddress!)
    }
  }

  private final class DrainSink: @unchecked Sendable {
    var data = Data()
  }
}
