import CompassAgentRPC
import Foundation

/// Pure Foundation file operations for the guest agent. These are the same
/// semantics as `AgentHostFilesystem` on the host, expressed against the
/// wire types so the dispatcher can hand back response payloads directly.
///
/// This binary runs as a LaunchAgent inside the user's GUI session and so
/// is in the right TCC context to read/write VirtioFS-mounted shares. The
/// caller (host) supplies absolute guest paths.
enum AgentFileOperations {

  static func readFile(at path: String) -> Result<
    AgentRPCResponse.ReadFileResult, AgentRPCResponse.Error
  > {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
      return .failure(AgentRPCResponse.Error(kind: .notFound, detail: path))
    }
    if isDirectory.boolValue {
      return .failure(AgentRPCResponse.Error(kind: .notRegularFile, detail: path))
    }
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      return .success(AgentRPCResponse.ReadFileResult(dataBase64: data.base64EncodedString()))
    } catch {
      return .failure(AgentRPCResponse.Error(kind: .ioFailure, detail: error.localizedDescription))
    }
  }

  static func writeFile(at path: String, dataBase64: String) -> Result<Void, AgentRPCResponse.Error>
  {
    guard let data = Data(base64Encoded: dataBase64) else {
      return .failure(
        AgentRPCResponse.Error(
          kind: .invalidArguments, detail: "writeFile: data is not valid base64"))
    }
    let fileManager = FileManager.default
    let url = URL(fileURLWithPath: path)
    let parent = url.deletingLastPathComponent()
    do {
      try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    } catch {
      return .failure(AgentRPCResponse.Error(kind: .ioFailure, detail: error.localizedDescription))
    }
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
      return .failure(AgentRPCResponse.Error(kind: .notRegularFile, detail: path))
    }
    do {
      try data.write(to: url, options: .atomic)
      return .success(())
    } catch {
      return .failure(AgentRPCResponse.Error(kind: .ioFailure, detail: error.localizedDescription))
    }
  }

  static func stat(at path: String) -> Result<AgentRPCResponse.StatResult, AgentRPCResponse.Error> {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
      return .success(AgentRPCResponse.StatResult(metadata: nil))
    }
    let url = URL(fileURLWithPath: path)
    let resourceValues = try? url.resourceValues(forKeys: [
      .fileSizeKey,
      .contentModificationDateKey,
      .isRegularFileKey,
    ])
    let metadata = AgentRPCResponse.FileMetadata(
      path: path,
      isDirectory: isDirectory.boolValue,
      isRegularFile: resourceValues?.isRegularFile ?? !isDirectory.boolValue,
      size: resourceValues?.fileSize,
      modificationDateEpoch: resourceValues?.contentModificationDate?.timeIntervalSince1970
    )
    return .success(AgentRPCResponse.StatResult(metadata: metadata))
  }

  static func listDirectory(at path: String) -> Result<
    AgentRPCResponse.ListDirectoryResult, AgentRPCResponse.Error
  > {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
      return .failure(AgentRPCResponse.Error(kind: .notFound, detail: path))
    }
    guard isDirectory.boolValue else {
      return .failure(AgentRPCResponse.Error(kind: .notDirectory, detail: path))
    }
    let url = URL(fileURLWithPath: path)
    let entries: [URL]
    do {
      entries = try fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
      )
    } catch {
      return .failure(AgentRPCResponse.Error(kind: .ioFailure, detail: error.localizedDescription))
    }
    let payload = entries.map { entryURL -> AgentRPCResponse.DirectoryEntry in
      var entryIsDir: ObjCBool = false
      fileManager.fileExists(atPath: entryURL.path, isDirectory: &entryIsDir)
      return AgentRPCResponse.DirectoryEntry(
        path: entryURL.path,
        name: entryURL.lastPathComponent,
        isDirectory: entryIsDir.boolValue
      )
    }
    return .success(AgentRPCResponse.ListDirectoryResult(entries: payload))
  }

  static func glob(pattern: String, rootPath: String, walkCap: Int) -> Result<
    AgentRPCResponse.GlobResult, AgentRPCResponse.Error
  > {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory), isDirectory.boolValue
    else {
      return .failure(AgentRPCResponse.Error(kind: .notDirectory, detail: rootPath))
    }
    let regex: NSRegularExpression
    do {
      regex = try GlobPattern.regex(forGlob: pattern)
    } catch {
      return .failure(
        AgentRPCResponse.Error(
          kind: .invalidArguments, detail: "invalid glob: \(error.localizedDescription)"))
    }
    let rootURL = URL(fileURLWithPath: rootPath)
    guard
      let enumerator = fileManager.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: []
      )
    else {
      return .failure(
        AgentRPCResponse.Error(kind: .ioFailure, detail: "could not enumerate \(rootPath)"))
    }
    let standardizedRoot = rootURL.standardizedFileURL.path
    let rootPrefix = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"

    var matches: [AgentRPCResponse.GlobMatch] = []
    var visited = 0
    while let next = enumerator.nextObject() {
      visited += 1
      if visited > walkCap { break }
      guard let fileURL = next as? URL else { continue }
      let absolute = fileURL.standardizedFileURL.path
      let relative: String
      if absolute == standardizedRoot {
        relative = "."
      } else if absolute.hasPrefix(rootPrefix) {
        relative = String(absolute.dropFirst(rootPrefix.count))
      } else {
        relative = absolute
      }
      let nsRelative = relative as NSString
      let range = NSRange(location: 0, length: nsRelative.length)
      if regex.firstMatch(in: relative, options: [], range: range) == nil { continue }
      let resourceValues = try? fileURL.resourceValues(forKeys: [
        .isRegularFileKey, .contentModificationDateKey,
      ])
      if resourceValues?.isRegularFile != true { continue }
      matches.append(
        AgentRPCResponse.GlobMatch(
          path: absolute,
          modificationDateEpoch: resourceValues?.contentModificationDate?.timeIntervalSince1970
        ))
    }
    return .success(AgentRPCResponse.GlobResult(matches: matches))
  }

  static func grep(
    pattern: String,
    path: String,
    glob: String?,
    caseInsensitive: Bool,
    timeoutSeconds: Double
  ) -> AgentRPCResponse.ProcessResult {
    let rgPath = "/opt/homebrew/bin/rg"
    let grepPath = "/usr/bin/grep"
    let executable: String
    let arguments: [String]
    if FileManager.default.isExecutableFile(atPath: rgPath) {
      executable = rgPath
      var args = ["--no-config", "--with-filename", "--line-number", "--color", "never"]
      if caseInsensitive { args.append("--ignore-case") }
      if let glob, !glob.isEmpty { args += ["--glob", glob] }
      args += [pattern, path]
      arguments = args
    } else {
      executable = grepPath
      var args = ["-rnE"]
      if caseInsensitive { args.append("-i") }
      if let glob, !glob.isEmpty { args += ["--include=\(glob)"] }
      args += [pattern, path]
      arguments = args
    }
    return runProcess(
      executable: executable,
      arguments: arguments,
      timeoutSeconds: timeoutSeconds
    )
  }

  static func bash(
    command: String,
    workingDirectory: String,
    timeoutSeconds: Double
  ) -> AgentRPCResponse.ProcessResult {
    runProcess(
      executable: "/bin/zsh",
      arguments: ["-lc", command],
      workingDirectory: workingDirectory,
      timeoutSeconds: timeoutSeconds
    )
  }

  // MARK: - Process runner

  private static func runProcess(
    executable: String,
    arguments: [String],
    workingDirectory: String? = nil,
    timeoutSeconds: Double
  ) -> AgentRPCResponse.ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let workingDirectory {
      process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    }
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    do {
      try process.run()
    } catch {
      return AgentRPCResponse.ProcessResult(
        exitCode: 127,
        stdout: "",
        stderr: "failed to launch \(executable): \(error.localizedDescription)"
      )
    }

    let pid = process.processIdentifier

    // Put the direct child into its own process group so any
    // grandchildren it spawns — including `cmd &` backgrounded jobs
    // and tools that fork helpers (swift build → swiftc/clang/ld) —
    // inherit the same pgid and can be reaped as a unit below. There
    // is a tiny window between fork and this setpgid where the child
    // could have already forked into the parent's group; in that case
    // the escapee leaks past this RPC and only a VM restart will
    // reclaim it. Acceptable in practice for the workloads agents run.
    _ = setpgid(pid, pid)

    // Drop the parent's copies of the pipe write ends so EOF arrives
    // on the read ends when the *direct* child closes them — not
    // after every grandchild that inherited the fds also closes them.
    // Without this, `./.build/debug/App 2>&1 &` returns from zsh
    // within milliseconds but the readToEnd() below never completes,
    // because the backgrounded App is still holding the write side
    // open.
    try? stdoutPipe.fileHandleForWriting.close()
    try? stderrPipe.fileHandleForWriting.close()

    // Drain stdout/stderr concurrently so a chatty child can't
    // deadlock against the ~64 KiB pipe buffer while we sit polling
    // `isRunning`. Each thread writes its captured Data into its own
    // sink; DispatchGroup.wait() below provides the happens-before
    // edge that lets us read them safely on this thread.
    final class DrainSink: @unchecked Sendable {
      var data = Data()
    }
    let stdoutSink = DrainSink()
    let stderrSink = DrainSink()
    let drainGroup = DispatchGroup()
    let stdoutHandle = stdoutPipe.fileHandleForReading
    let stderrHandle = stderrPipe.fileHandleForReading
    drainGroup.enter()
    DispatchQueue.global(qos: .utility).async {
      stdoutSink.data = (try? stdoutHandle.readToEnd()) ?? Data()
      drainGroup.leave()
    }
    drainGroup.enter()
    DispatchQueue.global(qos: .utility).async {
      stderrSink.data = (try? stderrHandle.readToEnd()) ?? Data()
      drainGroup.leave()
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    let timedOut = process.isRunning

    // SIGKILL the entire process group on both timeout AND clean
    // exit. The clean-exit case is the load-bearing one: it reaps
    // backgrounded grandchildren whose parent (zsh) already exited
    // successfully — without it those grandchildren would survive
    // the RPC, keep burning guest CPU between iterations, and (if
    // they inherited stdio) leave the drain threads above blocked
    // on EOF forever. ESRCH from an empty group is harmless.
    _ = kill(-pid, SIGKILL)
    if process.isRunning {
      let graceDeadline = Date().addingTimeInterval(1.0)
      while process.isRunning && Date() < graceDeadline {
        Thread.sleep(forTimeInterval: 0.05)
      }
    }

    drainGroup.wait()
    var stderrText = String(decoding: stderrSink.data, as: UTF8.self)
    if timedOut {
      if !stderrText.isEmpty && !stderrText.hasSuffix("\n") { stderrText += "\n" }
      stderrText += "[timed out after \(Int(timeoutSeconds * 1000)) ms]"
    }
    return AgentRPCResponse.ProcessResult(
      exitCode: process.terminationStatus,
      stdout: String(decoding: stdoutSink.data, as: UTF8.self),
      stderr: stderrText
    )
  }
}

/// Glob → regex translator, identical to the host-side `AgentGlobPattern`.
/// Duplicated here so the guest agent doesn't have to link the host's
/// agent-tool module just to share this one parser.
enum GlobPattern {
  static func regex(forGlob pattern: String) throws -> NSRegularExpression {
    var regex = "^"
    var i = pattern.startIndex
    while i < pattern.endIndex {
      let c = pattern[i]
      if c == "*" {
        let next = pattern.index(after: i)
        if next < pattern.endIndex, pattern[next] == "*" {
          regex += ".*"
          i = pattern.index(after: next)
          if i < pattern.endIndex && pattern[i] == "/" {
            i = pattern.index(after: i)
          }
          continue
        }
        regex += "[^/]*"
      } else if c == "?" {
        regex += "[^/]"
      } else if ".^$+(){}|[]\\".contains(c) {
        regex.append("\\")
        regex.append(c)
      } else {
        regex.append(c)
      }
      i = pattern.index(after: i)
    }
    regex += "$"
    return try NSRegularExpression(pattern: regex)
  }
}
