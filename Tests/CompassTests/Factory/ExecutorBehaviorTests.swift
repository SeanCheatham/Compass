import Foundation
import Testing
@testable import Compass
@testable import CompassCore

@Suite("Executor behavior")
struct ExecutorBehaviorTests {
@Test
  func executorRunsToolObservationThenSubmitWithFakeRuntime() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try "export const answer = 42\n".write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports.","note":"after-read-note: edit this file if it exports answer."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Read the file.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema
      )
    )

    #expect(result.iterations == 2)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 2)
    #expect(prompts[1].contains("export const answer"))
    #expect(prompts[1].contains("### Assistant Note (unverified)"))
    #expect(prompts[1].contains("after-read-note: edit this file if it exports answer."))
    if let observationRange = prompts[1].range(of: "### Compass Observation"),
      let noteRange = prompts[1].range(
        of: "### Assistant Note (unverified)",
        range: observationRange.upperBound..<prompts[1].endIndex
      )
    {
      let observationSection = String(prompts[1][observationRange.upperBound..<noteRange.lowerBound])
      #expect(!observationSection.contains("after-read-note"))
    } else {
      Issue.record("Expected separate observation and note sections")
    }
  }
@Test
  func executorReturnsToolFailureObservationAndCanRecover() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"missing.ts"},"reason":"Need current contents."}"#,
      #"{"kind":"develop_submit","payload":{"status":"blocked","summary":"The file is missing.","feedback":"Plan should pick an existing file or create missing.ts explicitly.","bypassVerify":true,"lessonEdits":[]}}"#,
    ])
    _ = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema
      )
    )

    let prompts = await runtime.capturedPrompts()
    #expect(prompts[1].contains(#""isError" : true"#) || prompts[1].contains(#""isError":true"#))
    #expect(prompts[1].contains("File not found"))
  }
@Test
  func executorEscalatesRepeatedIdenticalToolFailures() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    export function one() { return 1; }
    export function two() { return 2; }
    export function three() { return 3; }
    """.write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )
    let invalidEdit =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"index.ts","startLine":1,"endLine":1,"content":"import { next } from './next';\n\nexport function replacement() {\n  return next();\n}\n\nexport function extra() {\n  return 42;\n}"},"reason":"Replace the module."}"#

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports."}"#,
      invalidEdit,
      invalidEdit,
      #"{"kind":"develop_submit","payload":{"status":"blocked","summary":"The edit range needs correction.","feedback":"Use a different edit_file range based on read_file output.","bypassVerify":true,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool(), AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated the exact same failed `edit_file` call 2 times"))
    #expect(prompts[3].contains("Do not call `edit_file` again with the same arguments"))
    #expect(prompts[3].contains("use its concrete repair shape"))
    #expect(prompts[3].contains("whole-file replacement"))
    #expect(prompts[3].contains("Do not submit"))
    #expect(prompts[3].contains("failed/blocked"))
    #expect(prompts[3].contains("previous edit range was wrong"))
    #expect(prompts[3].contains(#""path":"index.ts""#))
  }
@Test
  func executorEscalatesRepeatedPartialRewriteFailureFamily() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    import { current } from "./current";
    export function one() { return 1; }
    export function two() { return 2; }
    export function three() { return 3; }
    export function four() { return 4; }
    export function five() { return 5; }
    """.write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )
    let replacement = """
    import { next } from './next';

    export function replacement() {
      return next();
    }

    export function extra() {
      return 42;
    }
    """
    let partialRewriteAtTop =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"index.ts","startLine":1,"endLine":1,"content":\#(jsonStringLiteral(replacement))},"reason":"Rewrite the module."}"#
    let partialRewriteShifted =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"index.ts","startLine":2,"endLine":2,"content":\#(jsonStringLiteral(replacement))},"reason":"Try a nearby range."}"#

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports."}"#,
      partialRewriteAtTop,
      partialRewriteShifted,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not repair the edit shape.","feedback":"The edit kept moving the same partial rewrite to nearby ranges.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool(), AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated `edit_file` failures in the same repair family"))
    #expect(prompts[3].contains("Failure family: partial whole-file rewrite"))
    #expect(prompts[3].contains("Changing only `startLine`/`endLine`"))
    #expect(prompts[3].contains("use the full file range"))
    #expect(prompts[3].contains("Do not move the same multi-line replacement"))
    #expect(prompts[3].contains("Latest failure"))
    #expect(prompts[3].contains(#""path":"index.ts""#))
  }
@Test
  func executorEscalatesRepeatedBodyOnlyFunctionReplacementFamily() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return title;
    }

    console.log(main());
    """.write(
      to: tempURL.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )
    let bodyOnly = """
      const count = Number.parseInt(argv[0] ?? "1", 10);
      const title = argv.slice(1).join(" ").trim() || "First Compass task";
      return `${count}: ${title}`;
    """
    let replaceDeclarationOnly =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"main.ts","startLine":1,"endLine":1,"content":\#(jsonStringLiteral(bodyOnly))},"reason":"Replace main logic."}"#
    let replaceDeclarationAndBody =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"main.ts","startLine":1,"endLine":3,"content":\#(jsonStringLiteral(bodyOnly))},"reason":"Try a wider range."}"#

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"main.ts"},"reason":"Need current main function."}"#,
      replaceDeclarationOnly,
      replaceDeclarationAndBody,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not repair the function edit.","feedback":"The edit kept replacing a declaration with body-only lines.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool(), AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated `edit_file` failures in the same repair family"))
    #expect(prompts[3].contains("Failure family: body-only function declaration replacement"))
    #expect(prompts[3].contains("include the complete function declaration"))
    #expect(prompts[3].contains("edit only the body lines inside the function"))
    #expect(prompts[3].contains("Do not replace a function declaration line"))
    #expect(prompts[3].contains("Concrete repair arguments from the latest Compass Observation"))
    #expect(prompts[3].contains("Use these as the `arguments` for the next `edit_file` call"))
    #expect(prompts[3].contains(#""path":"main.ts""#))
    #expect(prompts[3].contains(#""startLine":1"#))
    #expect(prompts[3].contains(#""endLine":4"#))
    #expect(prompts[3].contains("export function main(argv = process.argv.slice(2)): string {"))
  }
@Test
  func executorEscalatesRepeatedReadOnlyDevelopLoopBeforeSubmitRejection() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    export function main(argv = process.argv.slice(2)): string {
      return argv.join(" ");
    }
    """.write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )

    let readIndex =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current line numbers before editing."}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      readIndex,
      readIndex,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Did not edit the CLI.","feedback":"The model repeated reads instead of calling edit_file.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[2].contains("You repeated successful read-only Develop tool calls"))
    #expect(prompts[2].contains("Do not call `read_file` again with the same arguments"))
    #expect(prompts[2].contains("Choose exactly one next action"))
    #expect(prompts[2].contains("Call `edit_file` or `write_file`"))
    #expect(prompts[2].contains("status=failed or status=blocked"))
    #expect(prompts[2].contains(#""path":"index.ts""#))
  }
@Test
  func executorEscalatesAlternatingReadOnlyDevelopLoop() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let readSource =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/src/main.rs"},"reason":"Need current CLI logic before editing."}"#
    let readTest =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/tests/cli.rs"},"reason":"Need current tests before editing."}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      readSource,
      readTest,
      readSource,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Did not edit the CLI.","feedback":"The model alternated reads instead of calling edit_file.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    #expect(counter.value == 3)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated successful read-only Develop tool calls"))
    #expect(prompts[3].contains("read-only tool calls in a row without changing files"))
    #expect(prompts[3].contains("seen 2 time(s) in that streak"))
    #expect(prompts[3].contains("Do not keep calling\n`read_file`")
      || prompts[3].contains("Do not keep calling `read_file`"))
    #expect(prompts[3].contains("Call `edit_file` or `write_file`"))
    #expect(prompts[3].contains(#""path":"crates/cli/src/main.rs""#))
  }
@Test
  func executorRejectsToolCallAfterPlanSubmitRejection() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let planSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Build decision notes.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts."}"#
    let validator = RejectFirstPlanSubmitValidator()
    let runtime = FakeLocalModelRuntime(outputs: [
      planSubmit,
      readPackage,
      planSubmit,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 3,
        validateSubmitResult: { data in
          try validator.validate(data)
        }
      )
    )

    #expect(result.iterations == 3)
    #expect(counter.value == 0)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Your previous `plan_submit` payload could not be used"))
    #expect(prompts[1].contains("Required next shape:"))
    #expect(prompts[1].contains(#"{"kind":"plan_submit","payload":{...}}"#))
    #expect(!prompts[1].contains(#"Required shape:\n{"kind":"plan_continue""#))
    #expect(prompts[1].contains("Do not call `plan_continue`"))
    #expect(
      prompts[2].contains(
        "Your previous `plan_submit` was rejected because Compass rejected its payload"
      ))
    #expect(prompts[2].contains("The next action must repair that submit envelope"))
    #expect(prompts[2].contains("Compass did not run `read_file`"))
    #expect(prompts[2].contains("Do not call `read_file`, `list_files`, `bash`"))
    #expect(prompts[2].contains("For Plan, repair `state.immediate.plan` directly"))
    #expect(
      prompts[2].contains("Include both the target test file path and the concrete invocation"))
    #expect(prompts[2].contains(#"{"kind":"plan_submit","payload":{...}}"#))
    #expect(prompts[2].contains("Your previous Plan payload claimed new CLI behavior without proof"))
    #expect(prompts[2].contains("Do not call another tool to repair this"))
    #expect(prompts[2].contains(#"["--format", "json", "Ship", "it"]"#))
    #expect(prompts[2].contains(#""path":"package.json""#))
  }
@Test
  func executorEscalatesRepeatedToolCallsAfterMalformedContinuationRejection() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts."}"#
    let planSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Build decision notes.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      "not valid continuation json",
      readPackage,
      readPackage,
      planSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[1].contains("Your previous response could not be used"))
    #expect(prompts[3].contains("malformed Plan continuation response"))
    #expect(prompts[3].contains("called\n`read_file` with the same arguments 2 times")
      || prompts[3].contains("called `read_file` with the same arguments 2 times"))
    #expect(prompts[3].contains("did not repair the rejected continuation"))
    #expect(prompts[3].contains("Do not call `read_file`, `list_files`, or reread"))
    #expect(prompts[3].contains("Return `plan_submit` with a corrected `payload`"))
    #expect(prompts[3].contains("Latest continuation repair to apply now"))
    #expect(prompts[3].contains("Invalid response"))
    #expect(prompts[3].contains(#""path":"package.json""#))
  }
@Test
  func executorEscalatesRepeatedSubmitRejections() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let weakPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Add JSON CLI output.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      weakPlanSubmit,
      weakPlanSubmit,
      weakPlanSubmit,
    ])
    let validator = RejectFirstTwoPlanSubmitValidator()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 3,
        validateSubmitResult: { data in
          try validator.validate(data)
        }
      )
    )

    #expect(result.iterations == 3)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Your previous Plan payload claimed new CLI behavior without proof"))
    #expect(prompts[2].contains("Compass rejected `plan_submit` for the same reason 2 times"))
    #expect(prompts[2].contains("Do not return the same payload again"))
    #expect(prompts[2].contains("Plan repair checklist"))
    #expect(prompts[2].contains("Do not resubmit the same `state.immediate.plan`"))
    #expect(prompts[2].contains("Keep `state.immediate.verify` as `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace`"))
    #expect(prompts[2].contains(#"["--format", "json", "Ship", "it"]"#))
    #expect(prompts[2].contains("Latest rejected-payload repair to apply now"))
  }
@Test
  func executorGivesConcreteVerifyCommandAfterUnfinishedDevelopSuccess() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let unfinishedSubmit =
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Edited main.ts.","feedback":"Run `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` to check if the changes meet the acceptance criteria.","bypassVerify":false,"lessonEdits":[]}}"#
    let readPackage =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current package scripts."}"#
    let runVerify =
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run the missing verification command before submitting success."}"#
    let finishedSubmit =
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verified the completed packet.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      unfinishedSubmit,
      readPackage,
      readPackage,
      runVerify,
      finishedSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          AgentReadFileTool(),
          FakeBashTool(output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success."),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 5,
        validateSubmitResult: { data in
          let summary = try JSONDecoder().decode(DevelopSummary.self, from: data)
          try DevelopFeedbackValidator.validate(summary)
        }
      )
    )

    #expect(result.iterations == 5)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 5)
    #expect(prompts[1].contains("Detected missing verification command"))
    #expect(prompts[1].contains(#""tool": "bash""#))
    #expect(prompts[1].contains("cargo clippy"))
    #expect(prompts[1].contains("Do not call `read_file`"))
    #expect(prompts[3].contains("If the rejected payload said a verify command still needs to run"))
    #expect(prompts[3].contains("Do not call `read_file`, `list_files`, or reread"))
  }
@Test
  func executorRejectsFailedDevelopSubmitAfterSuccessfulVerify() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run verification."}"#,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Typecheck failed due to a missing summarizeQueue import.","feedback":"Fix the summarizeQueue import before trying again.","bypassVerify":false,"lessonEdits":[]}}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verification passed after the requested changes.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace; the packet is ready for Plan.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [FakeBashTool(output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success.")],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("Compass already observed this verify command pass"))
    #expect(prompts[2].contains("status=failed, bypassVerify=false"))
    #expect(prompts[2].contains("return `develop_submit` again with"))
  }
@Test
  func executorClearsSuccessfulVerifyAfterFileMutation() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run baseline verification."}"#,
      #"{"kind":"develop_continue","tool":"write_file","arguments":{"path":"generated.ts","content":"export const generated = true;\n"},"reason":"Repair missing acceptance check: generated.ts must exist after verify."}"#,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"A later file mutation still needs verification.","feedback":"Run cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace after generated.ts was created.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeBashTool(output: "[stdout]\nBaseline passed.\n\n[exit 0]\n\n[next]\nSubmit success."),
          AgentWriteFileTool(),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("failed"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("You just changed files with `write_file` after Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("That earlier verify result no longer proves the current worktree"))
    #expect(prompts[2].contains("call `bash` with `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` again"))
    #expect(!prompts[2].contains("Compass already observed this verify command pass"))
  }
@Test
  func executorRejectsGenericFileMutationAfterSuccessfulVerify() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run verification."}"#,
      #"{"kind":"develop_continue","tool":"write_file","arguments":{"path":"generated.ts","content":"export const generated = true;\n"},"reason":"Create the file after verify."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"The packet was already verified.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeBashTool(output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success."),
          AgentWriteFileTool(),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(!FileManager.default.fileExists(atPath: tempURL.appending(path: "generated.ts").path))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("A generic `write_file` call after a"))
    #expect(prompts[2].contains("passing verify would invalidate that proof"))
    #expect(prompts[2].contains("retry `write_file` only with a `reason`"))
    #expect(prompts[2].contains("explicitly names the missing acceptance check"))
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
  }
@Test
  func executorRejectsRepeatedVerifyAfterSuccessfulVerifyWithoutMutation() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bashCounter = ToolInvocationCounter()
    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run verification."}"#,
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run the missing verification command before submitting success."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verification passed for the requested packet.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeBashTool(
            output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success.",
            counter: bashCounter
          )
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(bashCounter.value == 1)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("Compass already observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("Do not rerun verify against the same worktree"))
    #expect(prompts[2].contains("call `edit_file` or `write_file` now"))
  }
@Test
  func executorRejectsFailedSubmitAfterMutationInvalidatesFailedVerify() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bashCounter = ToolInvocationCounter()
    let bashResults = ToolResultQueue([
      .failure("[stderr]\nRust compile error before repair.\n\n[exit 1]", kind: .bashFailure),
      .ok("[stdout]\nAll checks passed after repair.\n\n[exit 0]\n\n[next]\nSubmit success."),
    ])
    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run verification."}"#,
      #"{"kind":"develop_continue","tool":"write_file","arguments":{"path":"generated.ts","content":"export const generated = true;\n"},"reason":"Repair failed verification output."}"#,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Rust compile errors during verification still block the packet.","feedback":"Review Rust compile errors from cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace before trying again.","bypassVerify":false,"lessonEdits":[]}}"#,
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Rerun verification after the accepted repair."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verification passed after the repair.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace after the accepted repair; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeSequencedBashTool(results: bashResults, counter: bashCounter),
          AgentWriteFileTool(),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 5
      )
    )

    #expect(bashCounter.value == 2)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 5)
    #expect(prompts[2].contains("You just changed files with `write_file` after Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` fail"))
    #expect(prompts[2].contains("That earlier failure no longer proves the current worktree"))
    #expect(prompts[3].contains("Compass previously observed this verify command fail"))
    #expect(prompts[3].contains("Do not submit status=failed from stale"))
    #expect(prompts[3].contains("call `bash` with `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` again"))
  }
@Test
  func executorCompactsContinuationHistoryWithoutCountingAnAgentIteration() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    for index in 1...5 {
      try "export const answer\(index) = \(index)\n".write(
        to: tempURL.appending(path: "file\(index).ts"),
        atomically: true,
        encoding: .utf8
      )
    }

    let continues = (1...5).map { index in
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"file\#(index).ts"},"reason":"Read pass \#(index)."}"#
    }
    let summary = """
      Goal / Current Phase
      Develop is reading small fixture files before deciding.

      Established Facts
      Older summary from compactor.

      Files / Symbols
      Small fixture files have been read in prior turns.

      Errors / Repairs
      None.

      Current Step / Next Action
      Continue from the latest raw observation.
      """
    let runtime = FakeLocalModelRuntime(outputs: continues + [
      summary,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Compaction preserved enough context.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        settings: AgentRuntimeSettings(contextWindowTokens: 300),
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 6
      )
    )

    #expect(result.iterations == 6)
    #expect(result.tokenUsage.compactionCount == 1)
    #expect(result.tokenUsage.summaryTokens > 0)

    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 7)
    #expect(prompts[5].contains("## Raw History To Compact"))
    #expect(prompts[5].contains("## Latest Raw History Kept Verbatim"))

    let finalPrompt = prompts[6]
    #expect(finalPrompt.contains("## Compacted History"))
    #expect(finalPrompt.contains("lower authority than real `Compass Observation` entries"))
    #expect(finalPrompt.contains("Older summary from compactor"))
    #expect(finalPrompt.contains("Read pass 5."))
    #expect(!finalPrompt.contains("Read pass 1."))
  }
@Test
  func executorRepairsMalformedOutput() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      "I am done.",
      #"{"kind":"critic_submit","payload":{"verdict":"approve","summary":"No blockers.","feedback":""}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .critic,
        runtime: runtime,
        tools: [],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.criticSchema
      )
    )

    #expect(result.iterations == 2)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts[1].contains("could not be used"))
    #expect(prompts[1].contains("critic_submit"))
  }
@Test
  func executorEscalatesRepeatedMalformedSubmitJSONAcrossToolReads() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let malformedPlanSubmit = """
      ```json
      {
        "kind": "plan_submit",
        "payload": {
          "state": {
            "immediate": {
              "plan": "## Outcome\\nAdd count support.\\n\\n## Acceptance checks\\n- main(["--count", "3", "Ship", "it"]) returns 3 open / 3 total.",
              "verify": "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
            },
            "queue": [],
            "brief": {
              "summary": "Add count support.",
              "targetUsers": [],
              "desiredOutcomes": [],
              "constraints": [],
              "acceptanceSignals": []
            },
            "openQuestions": []
          },
          "lessonEdits": []
        }
      }
      ```
      """
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts."}"#
    let validPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Build decision notes.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedPlanSubmit,
      readPackage,
      malformedPlanSubmit,
      validPlanSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("Compass rejected malformed `plan_submit` JSON 2 times"))
    #expect(prompts[3].contains("This is a JSON syntax problem"))
    #expect(prompts[3].contains("Do not call\n`read_file`")
      || prompts[3].contains("Do not call `read_file`"))
    #expect(prompts[3].contains("quotes inside string fields must be escaped"))
    #expect(prompts[3].contains("For Plan, do not call more tools"))
    #expect(prompts[3].contains("Return exactly one valid JSON object now"))
  }
@Test
  func executorRejectsToolCallAfterMalformedSubmitJSON() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"main(["--done", "1", "Ship", "it"]) returns 0 open / 1 total."}}}}"#
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need scripts after the rejected submit."}"#
    let validPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Add separate --done argv support.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedPlanSubmit,
      readPackage,
      validPlanSubmit,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(counter.value == 0)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[2].contains("Your previous `plan_submit` was rejected because the JSON was malformed"))
    #expect(prompts[2].contains("Compass did not run `read_file`"))
    #expect(prompts[2].contains("must not call tools"))
    #expect(prompts[2].contains(#"{"kind":"plan_submit","payload":{...}}"#))
  }
@Test
  func executorEscalatesRepeatedToolCallAfterMalformedSubmitJSON() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"main(["--done", "1", "Ship", "it"]) returns 0 open / 1 total."}}}}"#
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need scripts after the rejected submit."}"#
    let validPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Add separate --done argv support.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedPlanSubmit,
      readPackage,
      readPackage,
      validPlanSubmit,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    #expect(counter.value == 0)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("tried the same blocked `read_file` call 2 times"))
    #expect(prompts[3].contains("Compass will keep rejecting tools"))
    #expect(prompts[3].contains("The continuation-contract `read_file package.json` shape is only an example"))
    #expect(prompts[3].contains("Your next response must be `plan_submit`, not `plan_continue`"))
    #expect(prompts[3].contains("For Plan, repair `state.immediate.plan` directly"))
    #expect(prompts[3].contains(#""path":"package.json""#))
  }
@Test
  func executorRejectsProceduralFailedDevelopSubmitAfterMalformedContinuation() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedEdit = """
      ```json
      {
        "kind": "develop_continue",
        "tool": "edit_file",
        "arguments": {
          "path": "crates/cli/src/main.rs",
          "startLine": 4,
          "endLine": 15,
          "content": `export function main() {
        return "bad";
      }`
        },
        "reason": "Repair the CLI entrypoint."
      }
      ```
      """
    let proceduralFailure =
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Failed to parse and apply the edit_file content due to malformed JSON.","feedback":"Correct the JSON formatting and try again.","bypassVerify":false,"lessonEdits":[]}}"#
    let terminalFailure =
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not complete the requested CLI change within the iteration budget.","feedback":"The --count implementation was not completed before the Develop iteration budget ended.","bypassVerify":false,"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedEdit,
      proceduralFailure,
      terminalFailure,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("iteration budget"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("JSON strings must use double quotes"))
    #expect(prompts[2].contains("reported status=failed after Compass had already rejected"))
    #expect(prompts[2].contains("This is not a terminal Develop result"))
    #expect(prompts[2].contains("Return a valid `develop_continue` with corrected JSON now"))
    #expect(prompts[2].contains("use `replacementLines` as an array of strings"))
  }
@Test
  func executorNudgesReadOnlyDetourAfterMalformedDevelopContinuation() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedEdit = """
      ```json
      {
        "kind": "develop_continue",
        "tool": "edit_file",
        "arguments": {
          "path": "crates/cli/src/main.rs",
          "startLine": 4,
          "endLine": 15,
          "content": `export function main() {
        return "bad";
      }`
        },
        "reason": "Repair the CLI entrypoint."
      }
      ```
      """
    let readPackage =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts after the malformed edit."}"#
    let terminalFailure =
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not complete the requested CLI change within the iteration budget.","feedback":"The implementation was not completed before the Develop iteration budget ended.","bypassVerify":false,"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedEdit,
      readPackage,
      terminalFailure,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(counter.value == 1)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[2].contains("You called read-only inspection tool `read_file`"))
    #expect(prompts[2].contains("reading more files does not repair malformed JSON"))
    #expect(prompts[2].contains("repair the rejected continuation now"))
    #expect(prompts[2].contains("using `edit_file` and `replacementLines` as an array of strings"))
    #expect(prompts[2].contains("Do not reread `package.json`"))
    #expect(prompts[2].contains("Latest malformed-continuation repair to apply now"))
    #expect(prompts[2].contains(#""path":"package.json""#))
  }
@Test
  func executorStopsAtMaxIterationsAndWallClock() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedRuntime = FakeLocalModelRuntime(outputs: ["nope"])
    await #expect(throws: AgentExecutionError.self) {
      try await AgentExecutor().run(
        testConfiguration(
          phase: .develop,
          runtime: malformedRuntime,
          tools: [],
          workingDirectory: tempURL,
          submitResultSchema: Prompts.developSchema,
          maxIterations: 1
        )
      )
    }

    let slowRuntime = FakeLocalModelRuntime(outputs: ["nope", "nope"], delayNanoseconds: 20_000_000)
    await #expect(throws: AgentExecutionError.self) {
      try await AgentExecutor().run(
        testConfiguration(
          phase: .develop,
          runtime: slowRuntime,
          tools: [],
          workingDirectory: tempURL,
          submitResultSchema: Prompts.developSchema,
          maxIterations: 4,
          wallClockTimeout: 0.001
        )
      )
    }
  }
}
