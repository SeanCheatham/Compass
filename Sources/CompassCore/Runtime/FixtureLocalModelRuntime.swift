import Foundation

public actor FixtureLocalModelRuntime: LocalModelGenerating {
  public struct Line: Decodable {
    public var text: String
  }

  private var outputs: [String]
  private var cursor = 0
  private let promptLogDirectory: URL?

  public init(outputs: [String], promptLogDirectory: URL? = nil) {
    self.outputs = outputs
    self.promptLogDirectory = promptLogDirectory
  }

  public init(jsonlURL: URL, promptLogDirectory: URL? = nil) throws {
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

  public func generateText(request: LocalModelGenerationRequest) async throws
    -> LocalModelGenerationResult
  {
    let artifacts = try promptLogDirectory.map {
      try PromptLogWriter.writePromptLog(request: request, turn: cursor + 1, in: $0)
    }
    guard cursor < outputs.count else {
      if let promptLogDirectory, let artifacts {
        try? PromptLogWriter.writeOutputLog(
          "Generation failed: \(HeadlessCompassError.fixtureExhausted.localizedDescription)\n",
          request: request,
          artifacts: artifacts,
          status: "failed",
          error: HeadlessCompassError.fixtureExhausted.localizedDescription,
          in: promptLogDirectory
        )
      }
      throw HeadlessCompassError.fixtureExhausted
    }
    let output = outputs[cursor]
    cursor += 1
    if let promptLogDirectory, let artifacts {
      try PromptLogWriter.writeOutputLog(
        output,
        request: request,
        artifacts: artifacts,
        status: "completed",
        in: promptLogDirectory
      )
    }
    let usage = AgentRunTokenUsage.estimated(
      inputCharacters: request.systemPrompt.count + request.prompt.count,
      outputCharacters: output.count,
      charsPerToken: AgentExecutor.estimatedCharsPerToken
    )
    return LocalModelGenerationResult(text: output, tokenUsage: usage)
  }
}
