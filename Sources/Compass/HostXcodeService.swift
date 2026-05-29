import Foundation

enum HostXcodeAction: String, Codable, Sendable, Equatable {
  case build
  case test
}

struct HostXcodeStatus: Sendable, Equatable {
  var isReady: Bool
  var developerDir: String?
  var xcodebuildPath: String?
  var version: String?
  var unavailableReason: String?

  static func ready(developerDir: String, xcodebuildPath: String, version: String) -> Self {
    Self(
      isReady: true,
      developerDir: developerDir,
      xcodebuildPath: xcodebuildPath,
      version: version,
      unavailableReason: nil
    )
  }

  static func unavailable(_ reason: String, developerDir: String? = nil) -> Self {
    Self(
      isReady: false,
      developerDir: developerDir,
      xcodebuildPath: nil,
      version: nil,
      unavailableReason: reason
    )
  }
}

protocol HostXcodeServicing: Sendable {
  func status() async -> HostXcodeStatus
  func run(
    action: HostXcodeAction,
    arguments: [String],
    timeout: TimeInterval
  ) async throws -> ProcessResult
  func runVerifyCommand(_ command: String, timeout: TimeInterval) async throws -> ProcessResult
}

enum HostXcodeError: LocalizedError, Equatable {
  case unavailable(String)
  case invalidArguments(String)
  case unsupportedVerifyCommand(String)

  var errorDescription: String? {
    switch self {
    case .unavailable(let reason):
      return reason
    case .invalidArguments(let detail):
      return "Invalid host Xcode arguments: \(detail)"
    case .unsupportedVerifyCommand(let detail):
      return "Unsupported host Xcode verify command: \(detail)"
    }
  }
}

struct HostXcodeService: HostXcodeServicing, @unchecked Sendable {
  var hostRepoURL: URL
  var guestWorkspacePath: String?
  var client: AgentVsockClient?
  var mirrorRootURL: URL
  var runner: ProcessRunner.InvocationRunner?

  init(
    hostRepoURL: URL,
    guestWorkspacePath: String? = nil,
    client: AgentVsockClient? = nil,
    mirrorRootURL: URL = HostXcodeService.defaultMirrorRootURL(),
    runner: ProcessRunner.InvocationRunner? = nil
  ) {
    self.hostRepoURL = hostRepoURL.standardizedFileURL
    self.guestWorkspacePath = guestWorkspacePath
    self.client = client
    self.mirrorRootURL = mirrorRootURL.standardizedFileURL
    self.runner = runner
  }

  static func defaultMirrorRootURL(fileManager: FileManager = .default) -> URL {
    let appSupport =
      (try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ))
      ?? URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
    return appSupport
      .appendingPathComponent("Compass", isDirectory: true)
      .appendingPathComponent("HostXcodeMirrors", isDirectory: true)
  }

  static func mirrorDirectory(forRepoURL repoURL: URL, rootURL: URL) -> URL {
    rootURL
      .appendingPathComponent(stableKey(for: repoURL.standardizedFileURL.path), isDirectory: true)
      .appendingPathComponent("worktree", isDirectory: true)
  }

  static func derivedDataDirectory(forRepoURL repoURL: URL, rootURL: URL) -> URL {
    rootURL
      .appendingPathComponent(stableKey(for: repoURL.standardizedFileURL.path), isDirectory: true)
      .appendingPathComponent("DerivedData", isDirectory: true)
  }

  static func stableKey(for value: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x100000001b3
    }
    return String(format: "%016llx", hash)
  }

  func status() async -> HostXcodeStatus {
    do {
      let developer = try await runLocal(
        executable: "/usr/bin/xcode-select",
        arguments: ["-p"],
        timeout: 10
      )
      let developerDir = developer.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      guard developer.exitCode == 0, !developerDir.isEmpty else {
        return .unavailable(
          "Host Xcode is not selected. Install Xcode and run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`."
        )
      }
      guard developerDir.contains(".app/Contents/Developer") else {
        return .unavailable(
          "Host developer directory points to \(developerDir), not full Xcode. Select an Xcode.app developer directory first.",
          developerDir: developerDir
        )
      }

      let found = try await runLocal(
        executable: "/usr/bin/xcrun",
        arguments: ["--find", "xcodebuild"],
        timeout: 10
      )
      let xcodebuildPath = found.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      guard found.exitCode == 0, !xcodebuildPath.isEmpty else {
        return .unavailable("Host `xcrun --find xcodebuild` failed: \(tail(found.stderr))")
      }

      let version = try await runLocal(
        executable: xcodebuildPath,
        arguments: ["-version"],
        timeout: 10
      )
      guard version.exitCode == 0 else {
        return .unavailable("Host `xcodebuild -version` failed: \(tail(version.stderr))")
      }

      let firstLaunch = try await runLocal(
        executable: xcodebuildPath,
        arguments: ["-checkFirstLaunchStatus"],
        timeout: 30
      )
      guard firstLaunch.exitCode == 0 else {
        return .unavailable(
          "Host Xcode first-launch tasks or license acceptance are incomplete. Open Xcode once or run `sudo xcodebuild -runFirstLaunch`. \(tail(firstLaunch.stdout + firstLaunch.stderr))"
        )
      }

      return .ready(
        developerDir: developerDir,
        xcodebuildPath: xcodebuildPath,
        version: version.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    } catch {
      return .unavailable("Host Xcode probe failed: \(error.localizedDescription)")
    }
  }

  func run(
    action: HostXcodeAction,
    arguments: [String],
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    let currentStatus = await status()
    guard currentStatus.isReady, let xcodebuildPath = currentStatus.xcodebuildPath else {
      throw HostXcodeError.unavailable(
        currentStatus.unavailableReason ?? "Host Xcode is not ready."
      )
    }
    let workingDirectory = try await prepareWorkingDirectory()
    let derivedData = Self.derivedDataDirectory(forRepoURL: hostRepoURL, rootURL: mirrorRootURL)
    try FileManager.default.createDirectory(
      at: derivedData.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let invocation = try Self.makeXcodebuildInvocation(
      xcodebuildPath: xcodebuildPath,
      action: action,
      arguments: arguments,
      workingDirectory: workingDirectory,
      derivedDataPath: derivedData
    )
    return try await runInvocation(invocation, timeout: timeout)
  }

  func runVerifyCommand(_ command: String, timeout: TimeInterval) async throws -> ProcessResult {
    let parsed = try Self.parseVerifyCommand(command)
    return try await run(action: parsed.action, arguments: parsed.arguments, timeout: timeout)
  }

  static func makeXcodebuildInvocation(
    xcodebuildPath: String,
    action: HostXcodeAction,
    arguments: [String],
    workingDirectory: URL,
    derivedDataPath: URL
  ) throws -> AgentExecutionInvocation {
    let cleaned = try validateXcodebuildArguments(arguments)
    var finalArguments = cleaned
    if !containsOption("-derivedDataPath", in: cleaned) {
      finalArguments.append(contentsOf: ["-derivedDataPath", derivedDataPath.path])
    }
    finalArguments.append(action.rawValue)
    return AgentExecutionInvocation(
      executable: xcodebuildPath,
      arguments: finalArguments,
      workingDirectory: workingDirectory
    )
  }

  static func parseVerifyCommand(_ command: String) throws -> (action: HostXcodeAction, arguments: [String]) {
    let words = try ShellWords.split(command)
    guard let executable = words.first else {
      throw HostXcodeError.unsupportedVerifyCommand("command is empty")
    }
    let executableName = URL(fileURLWithPath: executable).lastPathComponent
    guard executable == "xcodebuild" || executableName == "xcodebuild" else {
      throw HostXcodeError.unsupportedVerifyCommand(
        "expected an `xcodebuild ... build` or `xcodebuild ... test` command"
      )
    }
    var action: HostXcodeAction?
    var arguments: [String] = []
    for word in words.dropFirst() {
      if let parsedAction = HostXcodeAction(rawValue: word) {
        guard action == nil else {
          throw HostXcodeError.unsupportedVerifyCommand(
            "use exactly one xcodebuild action: build or test"
          )
        }
        action = parsedAction
      } else {
        arguments.append(word)
      }
    }
    guard let action else {
      throw HostXcodeError.unsupportedVerifyCommand(
        "verify command must include the xcodebuild action `build` or `test`"
      )
    }
    _ = try validateXcodebuildArguments(arguments)
    return (action, arguments)
  }

  private func prepareWorkingDirectory() async throws -> URL {
    guard let guestWorkspacePath, let client else {
      return hostRepoURL
    }
    let mirror = Self.mirrorDirectory(forRepoURL: hostRepoURL, rootURL: mirrorRootURL)
    try await SharedCompassVMWorktreeSync.refreshHostMirror(
      guestWorktreePath: guestWorkspacePath,
      hostMirrorURL: mirror,
      client: client
    )
    return mirror
  }

  private func runLocal(
    executable: String,
    arguments: [String],
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    try await runInvocation(
      AgentExecutionInvocation(executable: executable, arguments: arguments),
      timeout: timeout
    )
  }

  private func runInvocation(
    _ invocation: AgentExecutionInvocation,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    if let runner {
      return try await runner(invocation, nil, timeout, nil, nil)
    }
    return try await ProcessRunner.run(invocation: invocation, timeout: timeout)
  }

  private static func validateXcodebuildArguments(_ arguments: [String]) throws -> [String] {
    let disallowedActions: Set<String> = [
      "build", "test", "archive", "analyze", "clean", "install", "installhdrs", "installsrc",
    ]
    let shellOperators: Set<String> = ["&&", "||", ";", "|", "&", ">", "<", "2>", ">>"]
    return try arguments.map { raw in
      let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else {
        throw HostXcodeError.invalidArguments("empty argument")
      }
      guard !disallowedActions.contains(value) else {
        throw HostXcodeError.invalidArguments(
          "pass xcodebuild flags only; the tool action supplies `build` or `test`"
        )
      }
      guard !shellOperators.contains(value) else {
        throw HostXcodeError.invalidArguments("shell operators are not supported")
      }
      return value
    }
  }

  private static func containsOption(_ option: String, in arguments: [String]) -> Bool {
    arguments.contains(option)
  }

  private func tail(_ text: String, limit: Int = 600) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.suffix(limit))
  }
}

enum ShellWords {
  enum Error: LocalizedError, Equatable {
    case unterminatedQuote(Character)

    var errorDescription: String? {
      switch self {
      case .unterminatedQuote(let quote):
        return "Unterminated quote \(quote)"
      }
    }
  }

  static func split(_ command: String) throws -> [String] {
    var words: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false

    for character in command {
      if escaping {
        current.append(character)
        escaping = false
        continue
      }
      if character == "\\" {
        escaping = true
        continue
      }
      if let activeQuote = quote {
        if character == activeQuote {
          quote = nil
        } else {
          current.append(character)
        }
        continue
      }
      if character == "'" || character == "\"" {
        quote = character
        continue
      }
      if character.isWhitespace {
        if !current.isEmpty {
          words.append(current)
          current = ""
        }
        continue
      }
      current.append(character)
    }

    if escaping {
      current.append("\\")
    }
    if let quote {
      throw Error.unterminatedQuote(quote)
    }
    if !current.isEmpty {
      words.append(current)
    }
    return words
  }
}
