import Foundation

actor PromptLoggingLocalModelRuntime: LocalModelGenerating {
  private let base: any LocalModelGenerating
  private let promptLogDirectory: URL
  private var turn = 0

  init(base: any LocalModelGenerating, promptLogDirectory: URL) {
    self.base = base
    self.promptLogDirectory = promptLogDirectory
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    turn += 1
    let currentTurn = turn
    let artifacts = try PromptLogWriter.writePromptLog(
      request: request,
      turn: currentTurn,
      in: promptLogDirectory
    )
    do {
      let result = try await base.generateText(request: request)
      try PromptLogWriter.writeOutputLog(
        result.text,
        request: request,
        artifacts: artifacts,
        status: "completed",
        in: promptLogDirectory
      )
      return result
    } catch {
      try? PromptLogWriter.writeOutputLog(
        "Generation failed: \(error.localizedDescription)\n",
        request: request,
        artifacts: artifacts,
        status: "failed",
        error: error.localizedDescription,
        in: promptLogDirectory
      )
      throw error
    }
  }
}

struct PromptLogArtifacts: Equatable, Sendable {
  var turn: Int
  var label: String?
  var systemFilename: String
  var promptFilename: String
  var outputFilename: String
}

enum PromptLogWriter {
  static func writePromptLog(
    request: LocalModelGenerationRequest,
    turn: Int,
    in promptLogDirectory: URL
  ) throws -> PromptLogArtifacts {
    try FileManager.default.createDirectory(
      at: promptLogDirectory,
      withIntermediateDirectories: true
    )
    let label = sanitizedLabel(request.logLabel)
    let prefix = filenamePrefix(for: turn, label: label)
    let artifacts = PromptLogArtifacts(
      turn: turn,
      label: label,
      systemFilename: "\(prefix)-system.md",
      promptFilename: "\(prefix)-prompt.md",
      outputFilename: "\(prefix)-output.md"
    )
    try request.systemPrompt.write(
      to: promptLogDirectory.appending(path: artifacts.systemFilename),
      atomically: true,
      encoding: .utf8
    )
    try request.prompt.write(
      to: promptLogDirectory.appending(path: artifacts.promptFilename),
      atomically: true,
      encoding: .utf8
    )
    return artifacts
  }

  static func writeOutputLog(
    _ output: String,
    request: LocalModelGenerationRequest,
    artifacts: PromptLogArtifacts,
    status: String,
    error: String? = nil,
    in promptLogDirectory: URL
  ) throws {
    try FileManager.default.createDirectory(
      at: promptLogDirectory,
      withIntermediateDirectories: true
    )
    try output.write(
      to: promptLogDirectory.appending(path: artifacts.outputFilename),
      atomically: true,
      encoding: .utf8
    )
    try appendIndexEntry(
      PromptLogIndexEntry(
        turn: artifacts.turn,
        label: artifacts.label,
        status: status,
        modelID: request.modelID,
        systemFilename: artifacts.systemFilename,
        promptFilename: artifacts.promptFilename,
        outputFilename: artifacts.outputFilename,
        inputCharacters: request.systemPrompt.count + request.prompt.count,
        outputCharacters: output.count,
        maxOutputTokens: request.maxOutputTokens,
        error: error
      ),
      to: promptLogDirectory
    )
  }

  private static func filenamePrefix(for turn: Int, label: String?) -> String {
    let base = String(format: "%03d", turn)
    guard let label, !label.isEmpty else { return base }
    return "\(base)-\(label)"
  }

  private static func sanitizedLabel(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    let folded = raw.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
      .map { allowed.contains($0) ? String($0).lowercased() : "-" }
      .joined()
      .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
    guard !folded.isEmpty else { return nil }
    return String(folded.prefix(80))
  }

  private static func appendIndexEntry(
    _ entry: PromptLogIndexEntry,
    to promptLogDirectory: URL
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(entry)
    data.append(Data("\n".utf8))
    let url = promptLogDirectory.appending(path: "index.jsonl")
    if FileManager.default.fileExists(atPath: url.path) {
      let handle = try FileHandle(forWritingTo: url)
      handle.seekToEndOfFile()
      handle.write(data)
      try handle.close()
    } else {
      try data.write(to: url, options: .atomic)
    }
  }
}

private struct PromptLogIndexEntry: Encodable {
  var turn: Int
  var label: String?
  var status: String
  var modelID: String
  var systemFilename: String
  var promptFilename: String
  var outputFilename: String
  var inputCharacters: Int
  var outputCharacters: Int
  var maxOutputTokens: Int
  var error: String?
}
