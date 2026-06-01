import Foundation
import Testing

@testable import Compass

struct AgentExecutorLiveEventsTests {
  @Test func toolStartTitlesUseCommonAliasArguments() throws {
    let recorder = LiveEventRecorder()
    let executor = AgentExecutor { @Sendable event in
      recorder.record(event)
    }

    executor.emitToolStart(
      name: AgentBashTool.toolName,
      arguments: #"{"cmd":"swift test --filter LiveFailureInsightTests"}"#,
      correlationID: "bash-1"
    )
    executor.emitToolStart(
      name: AgentReadFileTool.toolName,
      arguments: #"{"file_path":"Sources/Compass/LiveFailureInsight.swift"}"#,
      correlationID: "read-1"
    )
    executor.emitToolStart(
      name: AgentGrepTool.toolName,
      arguments: #"{"query":"LiveFailureInsight","directory":"Sources/Compass"}"#,
      correlationID: "grep-1"
    )
    executor.emitToolStart(
      name: AgentFindSymbolTool.toolName,
      arguments: #"{"symbol_name":"LiveFailureInsight","symbol_kind":"struct"}"#,
      correlationID: "symbol-1"
    )
    executor.emitToolStart(
      name: AgentGenerateImageTool.toolName,
      arguments: #"{"image_prompt":"factory sketch","file_path":"art/factory.png"}"#,
      correlationID: "image-1"
    )

    let events = recorder.events
    try #require(events.map(\.text) == [
      "bash · swift test --filter LiveFailureInsightTests",
      "read_file · Sources/Compass/LiveFailureInsight.swift",
      "grep · LiveFailureInsight in Sources/Compass",
      "find_symbol · LiveFailureInsight (struct)",
      "generate_image · art/factory.png",
    ])
  }

  @Test func toolStartTitlesCoverFactoryServiceTools() throws {
    let recorder = LiveEventRecorder()
    let executor = AgentExecutor { @Sendable event in
      recorder.record(event)
    }

    executor.emitToolStart(
      name: AgentDelegateTool.toolName,
      arguments: #"{"instructions":"inspect the recovery guide"}"#,
      correlationID: "delegate-1"
    )
    executor.emitToolStart(
      name: AgentHostXcodeTool.toolName,
      arguments: #"{"operation":"test"}"#,
      correlationID: "xcode-1"
    )
    executor.emitToolStart(
      name: AgentInstallToolchainTool.toolName,
      arguments: #"{"toolchain_id":"rust"}"#,
      correlationID: "toolchain-1"
    )
    executor.emitToolStart(
      name: AgentPlanHistoryTool.toolName,
      arguments: #"{"skip":"2"}"#,
      correlationID: "history-1"
    )

    let events = recorder.events
    try #require(events.map(\.text) == [
      "delegate · inspect the recovery guide",
      "host_xcode · test",
      "install_toolchain · rust",
      "plan_history · offset 2",
    ])
  }
}

private final class LiveEventRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [LiveEvent] = []

  var events: [LiveEvent] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func record(_ event: LiveEvent) {
    lock.lock()
    defer { lock.unlock() }
    storage.append(event)
  }
}
