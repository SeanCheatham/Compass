import Foundation
import Testing

@testable import CompassCore

@Suite("CompassEngineRuntime")
struct CompassEngineRuntimeTests {
  @Test
  func embeddedEngineReportsExpectedVersionContract() async throws {
    let version = try await CompassEngineRuntime.shared.version()

    #expect(version.engineABIVersion == CompassEngineRuntime.expectedEngineABIVersion)
    #expect(
      version.projectReportSchemaVersion
        == CompassEngineRuntime.expectedProjectReportSchemaVersion
    )
    #expect(version.operations.contains("inspect_project"))
    #expect(version.operations.contains("check_source"))
  }

  @Test
  func verifiesScaffoldedTesseraProjectThroughEmbeddedEngine() async throws {
    let root = try makeEngineTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try TesseraProjectScaffold.write(to: root, options: .init(projectName: "Embedded App"))

    let result = try await CompassEngineProcess.verifyProject(root: root)

    #expect(result.exitCode == 0)
    #expect(result.stderr.isEmpty)
    #expect(result.stdout.contains(#""ok":true"#))
    #expect(result.stdout.contains(#""schema_version":1"#))
    #expect(result.stdout.contains(#""failures":[]"#))
    #expect(result.stdout.contains(#""trace""#))
    #expect(result.stdout.contains(#""executions""#))
  }

  @Test
  func inspectsTesseraProjectThroughEmbeddedEngine() async throws {
    let root = try makeEngineTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try TesseraProjectScaffold.write(to: root, options: .init(projectName: "Indexed App"))

    let inspection = try await CompassEngineProcess.loadProjectInspection(root: root)

    #expect(inspection.metadata.schemaVersion == 1)
    let source = try #require(
      inspection.sources.first { $0.path == "src/display-name.tes" }
    )
    #expect(source.symbols.contains { $0.name == "display" && $0.kind == "function" })
    #expect(source.entrypoints == ["cli", "web"])
    #expect(source.tests == ["tests/display-name.json"])
    #expect(source.contexts == ["contexts/user.json"])
  }

  @Test
  func focusedTesseraOperationsRunThroughEmbeddedEngine() async throws {
    let root = try makeEngineTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try TesseraProjectScaffold.write(to: root, options: .init(projectName: "Focused App"))

    let parsed = try await CompassEngineProcess.parseSource(root: root, path: "display-name")
    let checked = try await CompassEngineProcess.checkSource(
      root: root,
      path: "src/display-name.tes",
      input: Data(#"{"user":{"name":"Focused App"}}"#.utf8)
    )
    let formatted = try await CompassEngineProcess.formatSource(
      root: root,
      path: "src/display-name.tes"
    )
    let test = try await CompassEngineProcess.runTest(
      root: root,
      testPath: "tests/display-name.json"
    )

    #expect(parsed.exitCode == 0)
    #expect(parsed.stdout.contains(#""symbols""#))
    #expect(checked.exitCode == 0)
    #expect(checked.stdout.contains(#""ty":"Text""#))
    #expect(formatted.exitCode == 0)
    #expect(formatted.stdout.contains(#""source""#))
    #expect(test.exitCode == 0)
    #expect(test.stdout.contains(#""json":"focused-app!""#))
  }

  @Test
  func runsTesseraEntrypointThroughEmbeddedEngine() async throws {
    let root = try makeEngineTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try TesseraProjectScaffold.write(to: root, options: .init(projectName: "Embedded App"))

    let result = try await CompassEngineProcess.runEntrypoint(root: root, entrypoint: "cli")

    #expect(result.exitCode == 0)
    #expect(result.stdout.contains(#""name":"cli""#))
    #expect(result.stdout.contains(#""schema_version":1"#))
    #expect(result.stdout.contains(#""json":"embedded-app!""#))
  }

  @Test
  func embeddedVerifySummarizesTesseraExpectedActualFailures() async throws {
    let root = try makeEngineTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try TesseraProjectScaffold.write(to: root, options: .init(projectName: "Embedded App"))
    try """
      {
        "name": "display-name",
        "source": "display-name",
        "context": "user",
        "expect": "Grace!"
      }
      """.write(
        to: root.appending(path: "tests/display-name.json"),
        atomically: true,
        encoding: .utf8
      )

    let result = try await CompassEngineProcess.verifyProject(root: root)

    #expect(result.exitCode == 1)
    #expect(result.stdout.contains(#""failures""#))
    #expect(result.stderr.contains("Structured Tessera failures"))
    #expect(result.stderr.contains("Tessera test display-name"))
    #expect(result.stderr.contains("Tessera trace"))
    #expect(result.stderr.contains("expected"))
    #expect(result.stderr.contains(#""Grace!""#))
    #expect(result.stderr.contains(#""embedded-app!""#))
  }

  @Test
  func tesseraAgentToolVerifiesAndRunsEntrypoint() async throws {
    let root = try makeEngineTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try TesseraProjectScaffold.write(to: root, options: .init(projectName: "Tool App"))
    let tool = AgentTesseraTool()
    let context = AgentToolContext(workingDirectory: root)

    let verify = try await tool.invoke(
      arguments: Data(#"{"action":"verify"}"#.utf8),
      context: context
    )
    let run = try await tool.invoke(
      arguments: Data(#"{"action":"run_entrypoint","entrypoint":"cli"}"#.utf8),
      context: context
    )
    let inspect = try await tool.invoke(
      arguments: Data(#"{"action":"inspect_project"}"#.utf8),
      context: context
    )
    let check = try await tool.invoke(
      arguments: Data(#"{"action":"check_source","path":"display-name","input":{"user":{"name":"Tool App"}}}"#.utf8),
      context: context
    )

    #expect(!verify.isError)
    #expect(verify.content.contains("[exit 0]"))
    #expect(!run.isError)
    #expect(run.content.contains(#""json":"tool-app!""#))
    #expect(!inspect.isError)
    #expect(inspect.content.contains("Tessera project index"))
    #expect(!check.isError)
    #expect(check.content.contains(#""ty":"Text""#))
  }

  @Test
  func tesseraAgentToolReportsFailures() async throws {
    let root = try makeEngineTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root.appending(path: "src"),
      withIntermediateDirectories: true
    )
    try "(concat name \"!\")\n".write(
      to: root.appending(path: "src/display-name.tes"),
      atomically: true,
      encoding: .utf8
    )
    let tool = AgentTesseraTool()

    let result = try await tool.invoke(
      arguments: Data(#"{"action":"verify"}"#.utf8),
      context: AgentToolContext(workingDirectory: root)
    )

    #expect(result.isError)
    #expect(result.content.contains("[exit 1]"))
    #expect(result.content.contains("no Tessera project tests"))
  }

  @Test
  func headlessVerifyUsesEmbeddedTesseraInsteadOfBashRunner() async throws {
    let root = try makeEngineTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try TesseraProjectScaffold.write(to: root, options: .init(projectName: "Headless App"))
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    try ForgeProfileService.writeRecord(
      ForgeProfileRecord(profile: .tesseraApp, version: ForgeProfileRecord.currentVersion),
      workspace: workspace
    )
    let runner = RecordingFailingBashRunner()
    let compass = HeadlessCompassRunner { _, _ in runner }

    let ok = try await compass.verify(
      options: HeadlessVerifyOptions(repoURL: root, command: "tessera verify . --json"),
      onEvent: { _ in }
    )
    let calls = await runner.calls

    #expect(ok)
    #expect(calls.isEmpty)
  }

  @Test
  func codemapUsesEmbeddedTesseraInspection() async throws {
    let root = try makeEngineTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try TesseraProjectScaffold.write(to: root, options: .init(projectName: "Codemap App"))
    let store = CodemapStore(directory: root.appending(path: ".compass/codemap"))
    let indexer = CodemapIndexer(workingDirectory: root, store: store, minFileBytes: 0)

    let result = try await indexer.indexAll()
    let entry = try #require(store.loadEntry(forRelativePath: "src/display-name.tes"))

    #expect(result.failed == 0)
    #expect(entry.symbols.contains { $0.name == "display" && $0.kind == .function })
    #expect(entry.symbols.contains { $0.name == "entrypoint:cli" })
    #expect(entry.symbols.contains { $0.name == "test:display-name.json" })
    #expect(entry.imports.contains { $0.raw == "contexts/user.json" })
    #expect(entry.imports.contains { $0.raw == "tests/display-name.json" })
  }
}

private actor RecordingFailingBashRunner: AgentBashRunner {
  private(set) var calls: [String] = []

  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    calls.append(command)
    return ProcessResult(exitCode: 99, stdout: "", stderr: "bash should not run\n")
  }
}

private func makeEngineTempDirectory() throws -> URL {
  try makeCompassTestDirectory(named: "CompassEngineRuntimeTests")
}
