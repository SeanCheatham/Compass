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
    try writePromptLog(request: request, turn: currentTurn)
    do {
      let result = try await base.generateText(request: request)
      try writeOutputLog(result.text, turn: currentTurn)
      return result
    } catch {
      try? writeOutputLog("Generation failed: \(error.localizedDescription)\n", turn: currentTurn)
      throw error
    }
  }

  private func writePromptLog(request: LocalModelGenerationRequest, turn: Int) throws {
    try FileManager.default.createDirectory(
      at: promptLogDirectory,
      withIntermediateDirectories: true
    )
    let prefix = Self.filenamePrefix(for: turn)
    try request.systemPrompt.write(
      to: promptLogDirectory.appending(path: "\(prefix)-system.md"),
      atomically: true,
      encoding: .utf8
    )
    try request.prompt.write(
      to: promptLogDirectory.appending(path: "\(prefix)-prompt.md"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func writeOutputLog(_ output: String, turn: Int) throws {
    try FileManager.default.createDirectory(
      at: promptLogDirectory,
      withIntermediateDirectories: true
    )
    let prefix = Self.filenamePrefix(for: turn)
    try output.write(
      to: promptLogDirectory.appending(path: "\(prefix)-output.md"),
      atomically: true,
      encoding: .utf8
    )
  }

  private static func filenamePrefix(for turn: Int) -> String {
    String(format: "%03d", turn)
  }
}
