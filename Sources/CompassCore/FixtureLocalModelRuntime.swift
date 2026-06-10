import Foundation

actor FixtureLocalModelRuntime: LocalModelGenerating {
  struct Line: Decodable {
    var text: String
  }

  private var outputs: [String]
  private var cursor = 0
  private let promptLogDirectory: URL?

  init(outputs: [String], promptLogDirectory: URL? = nil) {
    self.outputs = outputs
    self.promptLogDirectory = promptLogDirectory
  }

  init(jsonlURL: URL, promptLogDirectory: URL? = nil) throws {
    let text = try String(contentsOf: jsonlURL, encoding: .utf8)
    var outputs: [String] = []
    let decoder = JSONDecoder()
    for (index, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      guard let data = line.data(using: .utf8) else { continue }
      do {
        outputs.append(try decoder.decode(Line.self, from: data).text)
      } catch {
        throw HeadlessCompassError.fixtureDecodeFailed(
          "Could not decode fixture line \(index + 1): \(error.localizedDescription)"
        )
      }
    }
    self.outputs = outputs
    self.promptLogDirectory = promptLogDirectory
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    try writePromptLog(request: request, turn: cursor + 1)
    guard cursor < outputs.count else {
      throw HeadlessCompassError.fixtureExhausted
    }
    let output = outputs[cursor]
    cursor += 1
    let usage = AgentRunTokenUsage.estimated(
      inputCharacters: request.systemPrompt.count + request.prompt.count,
      outputCharacters: output.count,
      charsPerToken: AgentExecutor.estimatedCharsPerToken
    )
    return LocalModelGenerationResult(text: output, tokenUsage: usage)
  }

  private func writePromptLog(request: LocalModelGenerationRequest, turn: Int) throws {
    guard let promptLogDirectory else { return }
    try FileManager.default.createDirectory(
      at: promptLogDirectory,
      withIntermediateDirectories: true
    )
    let prefix = String(format: "%03d", turn)
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
}
