import Foundation

/// Filesystem operations the agent tools need, behind a protocol so tools
/// don't call `FileManager` directly. Tools run host-side against the
/// worktree; `AgentHostFilesystem` in this file is the implementation.
public protocol AgentFilesystem: Sendable {
  /// Read a regular file's contents. Throws `.notFound` / `.notRegularFile`
  /// so the calling tool can surface a precise error.
  func readFile(at url: URL) async throws -> Data

  /// Atomically write bytes. Creates intermediate directories. Throws
  /// `.notRegularFile` if `url` is an existing directory.
  func writeFile(_ data: Data, at url: URL) async throws

  /// Returns metadata for `url`, or nil if the path does not exist.
  func metadata(of url: URL) async throws -> FileMetadata?

  /// One-level directory listing. Throws `.notFound` / `.notDirectory`.
  func listDirectory(at url: URL) async throws -> [DirectoryEntry]

  /// Walk `rootURL` recursively, returning regular files whose path
  /// relative to `rootURL` matches `pattern` (glob syntax: `**`, `*`,
  /// `?`). The walk is capped at `walkCap` total entries visited.
  func glob(pattern: String, under rootURL: URL, walkCap: Int) async throws -> [GlobMatch]

  /// Search `url` for `pattern` (regex). Implementations pick between
  /// `rg` and BSD `grep`. The returned `ProcessResult` keeps the tool's
  /// output formatting unchanged across backends.
  func grep(
    pattern: String,
    in url: URL,
    glob: String?,
    caseInsensitive: Bool,
    timeout: TimeInterval
  ) async throws -> ProcessResult
}

public struct FileMetadata: Sendable, Equatable {
  public var url: URL
  public var isDirectory: Bool
  public var isRegularFile: Bool
  public var size: Int?
  public var modificationDate: Date?
}

public struct DirectoryEntry: Sendable, Equatable {
  public var url: URL
  public var name: String
  public var isDirectory: Bool
}

public struct GlobMatch: Sendable, Equatable {
  public var url: URL
  public var modificationDate: Date?
}

public enum AgentFilesystemError: LocalizedError, Equatable {
  case notFound(URL)
  case notRegularFile(URL)
  case notDirectory(URL)
  case ioFailure(String)
  case transportFailure(String)

  public var errorDescription: String? {
    switch self {
    case .notFound(let url): return "File not found: \(url.path)"
    case .notRegularFile(let url): return "Not a regular file: \(url.path)"
    case .notDirectory(let url): return "Not a directory: \(url.path)"
    case .ioFailure(let detail): return "I/O failure: \(detail)"
    case .transportFailure(let detail): return "Filesystem transport failure: \(detail)"
    }
  }
}

/// Host-side `FileManager` implementation. Used when Compass runs entirely
/// on the host (no VM bash route) and as the implicit default for unit
/// tests, which construct `AgentToolContext` with just a working directory.
public struct AgentHostFilesystem: AgentFilesystem {
  public let grepExecutable: AgentGrepExecutable

  public init(grepExecutable: AgentGrepExecutable = AgentGrepExecutable.locate()) {
    self.grepExecutable = grepExecutable
  }

  public func readFile(at url: URL) async throws -> Data {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      throw AgentFilesystemError.notFound(url)
    }
    if isDirectory.boolValue {
      throw AgentFilesystemError.notRegularFile(url)
    }
    do {
      return try Data(contentsOf: url)
    } catch {
      throw AgentFilesystemError.ioFailure(error.localizedDescription)
    }
  }

  public func writeFile(_ data: Data, at url: URL) async throws {
    let fileManager = FileManager.default
    let parent = url.deletingLastPathComponent()
    do {
      try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    } catch {
      throw AgentFilesystemError.ioFailure(error.localizedDescription)
    }
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
      throw AgentFilesystemError.notRegularFile(url)
    }
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw AgentFilesystemError.ioFailure(error.localizedDescription)
    }
  }

  public func metadata(of url: URL) async throws -> FileMetadata? {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return nil
    }
    let resourceValues = try? url.resourceValues(forKeys: [
      .fileSizeKey,
      .contentModificationDateKey,
      .isRegularFileKey,
    ])
    return FileMetadata(
      url: url.standardizedFileURL,
      isDirectory: isDirectory.boolValue,
      isRegularFile: resourceValues?.isRegularFile ?? !isDirectory.boolValue,
      size: resourceValues?.fileSize,
      modificationDate: resourceValues?.contentModificationDate
    )
  }

  public func listDirectory(at url: URL) async throws -> [DirectoryEntry] {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      throw AgentFilesystemError.notFound(url)
    }
    guard isDirectory.boolValue else {
      throw AgentFilesystemError.notDirectory(url)
    }
    let entries: [URL]
    do {
      entries = try fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
      )
    } catch {
      throw AgentFilesystemError.ioFailure(error.localizedDescription)
    }
    return entries.map { entryURL in
      var entryIsDir: ObjCBool = false
      fileManager.fileExists(atPath: entryURL.path, isDirectory: &entryIsDir)
      return DirectoryEntry(
        url: entryURL,
        name: entryURL.lastPathComponent,
        isDirectory: entryIsDir.boolValue
      )
    }
  }

  public func glob(pattern: String, under rootURL: URL, walkCap: Int) async throws -> [GlobMatch] {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw AgentFilesystemError.notDirectory(rootURL)
    }

    let regex: NSRegularExpression
    do {
      regex = try AgentGlobPattern.regex(forGlob: pattern)
    } catch {
      throw AgentFilesystemError.ioFailure("invalid glob pattern: \(error.localizedDescription)")
    }

    guard
      let enumerator = fileManager.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: []
      )
    else {
      throw AgentFilesystemError.ioFailure("could not enumerate \(rootURL.path)")
    }

    var matches: [GlobMatch] = []
    var visited = 0
    let rootPath = rootURL.standardizedFileURL.path
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

    while let next = enumerator.nextObject() {
      visited += 1
      if visited > walkCap { break }
      guard let fileURL = next as? URL else { continue }

      let absolute = fileURL.standardizedFileURL.path
      let relative: String
      if absolute == rootPath {
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
        GlobMatch(
          url: fileURL,
          modificationDate: resourceValues?.contentModificationDate
        ))
    }
    return matches
  }

  public func grep(
    pattern: String,
    in url: URL,
    glob: String?,
    caseInsensitive: Bool,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    let searchTargetIsDirectory = exists && isDirectory.boolValue
    let workingDirectory = searchTargetIsDirectory ? url : url.deletingLastPathComponent()
    let invocationArgs: [String]
    switch grepExecutable {
    case .ripgrep:
      var rgArgs = [
        "--no-config",
        "--with-filename",
        "--line-number",
        "--color", "never",
      ]
      if caseInsensitive { rgArgs.append("--ignore-case") }
      if let glob, !glob.isEmpty {
        rgArgs += ["--glob", glob]
      }
      rgArgs += [pattern, url.path]
      invocationArgs = rgArgs

    case .grep:
      var grepArgs = ["-rnE"]
      if caseInsensitive { grepArgs.append("-i") }
      if searchTargetIsDirectory, let glob, !glob.isEmpty {
        let matches = try await self.glob(pattern: glob, under: url, walkCap: 10_000)
        let filePaths = matches.map(\.url.path)
        guard !filePaths.isEmpty else {
          return ProcessResult(exitCode: 1, stdout: "", stderr: "")
        }
        grepArgs.append(pattern)
        grepArgs += filePaths
        invocationArgs = grepArgs
        break
      }
      grepArgs += [pattern, url.path]
      invocationArgs = grepArgs
    }
    do {
      return try await ProcessRunner.run(
        executable: grepExecutable.path,
        arguments: invocationArgs,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
    } catch {
      throw AgentFilesystemError.ioFailure("grep launch failed: \(error.localizedDescription)")
    }
  }
}

/// Which grep-style executable to invoke. Picked once at startup so the
/// tool implementations don't re-stat `/opt/homebrew/bin/rg` on every call.
public enum AgentGrepExecutable: Sendable, Equatable {
  case ripgrep(String)
  case grep(String)

  public var path: String {
    switch self {
    case .ripgrep(let p): return p
    case .grep(let p): return p
    }
  }

  public static func locate() -> AgentGrepExecutable {
    let rgCandidates = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"]
    for path in rgCandidates where FileManager.default.isExecutableFile(atPath: path) {
      return .ripgrep(path)
    }
    return .grep("/usr/bin/grep")
  }
}

/// Glob pattern → regex translator, factored out of `AgentGlobTool` so
/// other filesystem implementations (e.g. a guest/VM-backed one) can share
/// the same pattern semantics without depending on the tool type.
public enum AgentGlobPattern {
  /// Translate a glob pattern into an anchored regex.
  /// - `**` matches any sequence of characters (including `/`).
  /// - `*` matches any characters except `/`.
  /// - `?` matches a single character except `/`.
  /// - All other regex metacharacters are escaped.
  public static func regex(forGlob pattern: String) throws -> NSRegularExpression {
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
