import CompassAgentRPC
import Darwin
import Foundation

/// Pure Foundation file operations for the guest agent. These are the same
/// semantics as `AgentHostFilesystem` on the host, expressed against the
/// wire types so the dispatcher can hand back response payloads directly.
///
/// This binary runs as a LaunchDaemon with `UserName=compass`. The caller
/// (host) supplies absolute paths under the synced guest workspace
/// (`/Users/compass/Compass/Repos/<catalog-id>/worktree`). File ops are
/// jails to that repos root (including sync staging siblings of
/// `worktree`). Bash working directories may also be the guest home (or
/// `/` / `/tmp` for host readiness/toolchain probes).
enum AgentFileOperations {
  /// Must stay aligned with `SharedCompassVMGuestLayout.currentMacOS.reposRoot`.
  static let allowedReposRoot = "/Users/compass/Compass/Repos"
  /// Must stay aligned with `SharedCompassVMGuestLayout.currentMacOS.homeDirectory`.
  static let allowedHomeRoot = "/Users/compass"

  static func assertPathInsideReposJail(_ path: String) -> AgentRPCResponse.Error? {
    let standardized = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    let root = URL(fileURLWithPath: allowedReposRoot).standardizedFileURL.path
    guard standardized == root || standardized.hasPrefix(root + "/") else {
      return AgentRPCResponse.Error(
        kind: .invalidArguments,
        detail:
          "path escapes guest repos jail (\(allowedReposRoot)): \(path)"
      )
    }
    return nil
  }

  /// Bash probes and toolchain installers often use `/` or `/tmp` as cwd;
  /// agent work uses the guest home / repos tree. Reject anything else so
  /// a `cd /etc`-style workingDirectory cannot be planted by the host RPC.
  static func assertBashWorkingDirectoryAllowed(_ path: String) -> AgentRPCResponse.Error? {
    let standardized = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    if standardized == "/" || standardized == "/tmp" || standardized.hasPrefix("/tmp/") {
      return nil
    }
    let home = URL(fileURLWithPath: allowedHomeRoot).standardizedFileURL.path
    if standardized == home || standardized.hasPrefix(home + "/") {
      return nil
    }
    return AgentRPCResponse.Error(
      kind: .invalidArguments,
      detail:
        "bash working directory escapes guest home jail (\(allowedHomeRoot)): \(path)"
    )
  }

  static func readFile(at path: String) -> Result<
    AgentRPCResponse.ReadFileResult, AgentRPCResponse.Error
  > {
    if let escape = assertPathInsideReposJail(path) {
      return .failure(escape)
    }
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
    if let escape = assertPathInsideReposJail(path) {
      return .failure(escape)
    }
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
    if let escape = assertPathInsideReposJail(path) {
      return .failure(escape)
    }
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
    if let escape = assertPathInsideReposJail(path) {
      return .failure(escape)
    }
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
    if let escape = assertPathInsideReposJail(rootPath) {
      return .failure(escape)
    }
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
    if let escape = assertPathInsideReposJail(path) {
      return AgentRPCResponse.ProcessResult(exitCode: 126, stdout: "", stderr: escape.detail)
    }
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
    if let escape = assertBashWorkingDirectoryAllowed(workingDirectory) {
      return AgentRPCResponse.ProcessResult(
        exitCode: 126,
        stdout: "",
        stderr: escape.detail
      )
    }
    return runProcess(
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
    // LaunchDaemon supplies HOME=/var/empty and a bare PATH. Fix both
    // from the account database so rustup proxies ($HOME/.rustup) and
    // /usr/local/bin symlinks (cargo, rg) work in spawned commands.
    var environment = ProcessInfo.processInfo.environment
    if let pwent = getpwuid(getuid()) {
      environment["HOME"] = String(cString: pwent.pointee.pw_dir)
    }
    environment["PATH"] =
      "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    // Homebrew OpenSSL is keg-only; point openssl-sys (and similar) at it when present.
    let opensslDir = "/opt/homebrew/opt/openssl"
    if FileManager.default.fileExists(atPath: opensslDir) {
      environment["OPENSSL_DIR"] = opensslDir
      let pkgConfigPath = "\(opensslDir)/lib/pkgconfig"
      if let existing = environment["PKG_CONFIG_PATH"], !existing.isEmpty {
        environment["PKG_CONFIG_PATH"] = "\(pkgConfigPath):\(existing)"
      } else {
        environment["PKG_CONFIG_PATH"] = pkgConfigPath
      }
    }
    return GuestProcess.run(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeoutSeconds: timeoutSeconds
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
