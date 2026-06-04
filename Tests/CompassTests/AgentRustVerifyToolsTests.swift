import Foundation
import Testing

@testable import Compass

struct AgentRustVerifyToolsTests {
  @Test func coverageGapsFormatsOverallPercent() async throws {
    let service = FakeRustVerifyService(
      data: encodeVerifyEnvelope(
        command: "coverage-gaps",
        data: CoverageGapsData(
          overallLinePercent: 72.5,
          files: [],
          logTail: "summary"
        )
      )
    )
    let result = try await AgentCoverageGapsTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: AgentToolContext(
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        rustCargoService: service
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("72.5%"))
  }

  @Test func visualVerifyFormatsScreenshotPath() async throws {
    let service = FakeRustVerifyService(
      data: encodeVerifyEnvelope(
        command: "visual-verify",
        data: VisualVerifyData(
          ok: true,
          screenshotPath: ".compass/visual-verify/latest.png",
          logTail: "ok"
        )
      )
    )
    let result = try await AgentVisualVerifyTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: AgentToolContext(
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        rustCargoService: service
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains(".compass/visual-verify/latest.png"))
  }
}

private func encodeVerifyEnvelope<T: Codable & Equatable>(command: String, data: T) -> Data {
  let response = RustEngineResponse(
    schemaVersion: 1,
    command: command,
    ok: true,
    data: data,
    errors: []
  )
  return try! JSONEncoder().encode(response)
}

private actor FakeRustVerifyService: RustCargoServicing {
  let data: Data

  init(data: Data) {
    self.data = data
  }

  func run(
    command: RustEngineCommand,
    repoURL: URL,
    arguments: [String],
    timeout: TimeInterval
  ) async throws -> Data {
    data
  }
}
