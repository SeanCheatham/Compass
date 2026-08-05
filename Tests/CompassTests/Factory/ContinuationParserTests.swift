import Foundation
import Testing
@testable import Compass
@testable import CompassCore

@Suite("Continuation parser")
struct ContinuationParserTests {
@Test
  func continuationParserAcceptsValidContinuePerPhase() throws {
    let tools: Set<String> = ["read_file", "bash"]
    for phase in AgentContinuationPhase.allCases {
      let json = """
        {
          "kind": "\(phase.continueKind)",
          "tool": "read-file",
          "arguments": { "path": "package.json" },
          "reason": "Need scripts.",
          "note": "  If scripts exist, choose the matching verify command.  "
        }
        """
      let parsed = try AgentContinuationParser.parse(
        json,
        phase: phase,
        availableToolNames: tools
      )
      guard case .continueTool(let toolName, let arguments, let reason, let note) = parsed.action else {
        Issue.record("Expected continue action")
        return
      }
      #expect(toolName == "read_file")
      #expect(String(decoding: arguments, as: UTF8.self).contains("package.json"))
      #expect(reason == "Need scripts.")
      #expect(note == "If scripts exist, choose the matching verify command.")
    }
  }
@Test
  func continuationParserUnwrapsSingleJSONCodeFence() throws {
    let json = """
      ```json
      {
        "kind": "plan_continue",
        "tool": "read_file",
        "arguments": {
          "path": "package.json"
        },
        "reason": "Need current package scripts."
      }
      ```
      """
    let parsed = try AgentContinuationParser.parse(
      json,
      phase: .plan,
      availableToolNames: ["read_file"]
    )

    guard case .continueTool(let toolName, let arguments, let reason, let note) = parsed.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(toolName == "read_file")
    #expect(String(decoding: arguments, as: UTF8.self).contains("package.json"))
    #expect(reason == "Need current package scripts.")
    #expect(note == nil)
  }
@Test
  func continuationParserSanitizesAndRejectsNotes() throws {
    let emptyNote = try AgentContinuationParser.parse(
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"note":"   "}"#,
      phase: .develop,
      availableToolNames: ["read_file"]
    )
    guard case .continueTool(_, _, _, let empty) = emptyNote.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(empty == nil)

    let longNote = String(repeating: "x", count: AgentContinuationParser.noteCharacterLimit + 20)
    let longJSON = """
      {"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"note":"\(longNote)"}
      """
    let truncated = try AgentContinuationParser.parse(
      longJSON,
      phase: .develop,
      availableToolNames: ["read_file"]
    )
    guard case .continueTool(_, _, _, let note) = truncated.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(note?.count == AgentContinuationParser.noteCharacterLimit)

    #expect(throws: AgentContinuationParseError.noteNotString) {
      try AgentContinuationParser.parse(
        #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"note":{"next":"edit"}}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
  }
@Test
  func continuationParserAcceptsValidSubmitPerPhase() throws {
    let payloads: [AgentContinuationPhase: String] = [
      .plan: #"{"state":{"immediate":null,"queue":[],"brief":{"summary":"","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}"#,
      .develop: #"{"status":"succeeded","summary":"Done","feedback":"Verified cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace","bypassVerify":false,"lessonEdits":[]}"#,
      .critic: #"{"verdict":"approve","summary":"No blockers","feedback":""}"#,
      .delegate: #"{"findings":"No blockers found."}"#,
    ]

    for phase in AgentContinuationPhase.allCases {
      let json = #"{"kind":"\#(phase.submitKind)","payload":\#(payloads[phase]!)}"#
      let parsed = try AgentContinuationParser.parse(
        json,
        phase: phase,
        availableToolNames: []
      )
      guard case .submit(let payload) = parsed.action else {
        Issue.record("Expected submit action")
        return
      }
      #expect(!payload.isEmpty)
    }
  }
@Test
  func continuationParserRejectsMalformedAndInvalidContinuations() {
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse("not json", phase: .develop, availableToolNames: [])
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        """
        Here is the JSON:
        ```json
        {"kind":"develop_continue","tool":"read_file","arguments":{}}
        ```
        """,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        #"{"kind":"plan_continue","tool":"read_file","arguments":{}}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        #"{"kind":"develop_continue","tool":"missing","arguments":{}}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        #"{"kind":"develop_continue","tool":"read_file","arguments":[]}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
  }
@Test
  func continuationParserExplainsBacktickTemplateLiteralJSON() {
    do {
      _ = try AgentContinuationParser.parse(
        """
        {
          "kind": "develop_continue",
          "tool": "edit_file",
          "arguments": {
            "path": "crates/cli/src/main.rs",
            "startLine": 1,
            "endLine": 1,
            "content": `const one = 1;
        const two = 2;`
          }
        }
        """,
        phase: .develop,
        availableToolNames: ["edit_file"]
      )
      Issue.record("Expected malformed JSON error")
    } catch let error as AgentContinuationParseError {
      let message = error.errorDescription ?? ""
      #expect(message.contains("backtick/template-literal strings are invalid"))
      #expect(message.contains("replacementLines as an array with one source line per string"))
      #expect(message.contains("Do not wrap content in backticks"))
    } catch {
      Issue.record("Expected AgentContinuationParseError, got \(error)")
    }
  }
}
