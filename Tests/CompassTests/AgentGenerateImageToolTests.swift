import Foundation
import XCTest

@testable import Compass

final class AgentGenerateImageToolTests: XCTestCase {
  private var workingDirectory: URL!
  private var filesystem: AgentHostFilesystem!

  override func setUpWithError() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-generate-image-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    workingDirectory = base.standardizedFileURL
    filesystem = AgentHostFilesystem()
  }

  override func tearDownWithError() throws {
    if let workingDirectory {
      try? FileManager.default.removeItem(at: workingDirectory)
    }
    workingDirectory = nil
    filesystem = nil
  }

  // MARK: - Tool behavior

  func testInvokeWritesBytesToOutputPath() async throws {
    let imageBytes = Data((0..<32).map { UInt8($0) })
    let generator = StubImageGenerator(result: .success(imageBytes))
    let assignment = MediaAssignment(
      provider: .minimaxToken,
      baseURL: URL(string: "https://api.minimax.io/v1")!,
      apiKey: "k",
      model: "image-01"
    )
    let tool = AgentGenerateImageTool(assignment: assignment, generator: generator)
    let context = AgentToolContext(workingDirectory: workingDirectory, filesystem: filesystem)

    let args = #"{"prompt": "a cat on a mat", "output_path": "out/hero.png"}"#
    let result = try await tool.invoke(arguments: Data(args.utf8), context: context)
    XCTAssertFalse(result.isError, "tool reported failure: \(result.content)")
    XCTAssertTrue(result.content.contains("out/hero.png"))

    let written = try Data(contentsOf: workingDirectory.appendingPathComponent("out/hero.png"))
    XCTAssertEqual(written, imageBytes)
    XCTAssertEqual(generator.recordedPrompts, ["a cat on a mat"])
    XCTAssertEqual(generator.recordedAssignments.map(\.provider), [.minimaxToken])
  }

  func testInvokeRejectsUnsupportedExtension() async throws {
    let generator = StubImageGenerator(result: .success(Data([0])))
    let tool = AgentGenerateImageTool(
      assignment: stubAssignment(),
      generator: generator
    )
    let context = AgentToolContext(workingDirectory: workingDirectory, filesystem: filesystem)
    let args = #"{"prompt": "x", "output_path": "out/hero.bmp"}"#
    let result = try await tool.invoke(arguments: Data(args.utf8), context: context)
    XCTAssertTrue(result.isError)
    XCTAssertEqual(result.errorKind, .invalidArguments)
    XCTAssertEqual(generator.recordedPrompts, [], "generator should not be invoked on bad ext")
  }

  func testInvokeRejectsEmptyPrompt() async throws {
    let generator = StubImageGenerator(result: .success(Data([0])))
    let tool = AgentGenerateImageTool(
      assignment: stubAssignment(),
      generator: generator
    )
    let context = AgentToolContext(workingDirectory: workingDirectory, filesystem: filesystem)
    let args = #"{"prompt": "   ", "output_path": "out/x.png"}"#
    let result = try await tool.invoke(arguments: Data(args.utf8), context: context)
    XCTAssertTrue(result.isError)
    XCTAssertEqual(result.errorKind, .invalidArguments)
  }

  func testInvokeRejectsPathEscape() async throws {
    let generator = StubImageGenerator(result: .success(Data([0])))
    let tool = AgentGenerateImageTool(
      assignment: stubAssignment(),
      generator: generator
    )
    let context = AgentToolContext(workingDirectory: workingDirectory, filesystem: filesystem)
    let args = #"{"prompt": "ok", "output_path": "/etc/passwd.png"}"#
    let result = try await tool.invoke(arguments: Data(args.utf8), context: context)
    XCTAssertTrue(result.isError)
    XCTAssertEqual(result.errorKind, .pathEscape)
  }

  func testGeneratorFailureSurfacesAsToolError() async throws {
    let generator = StubImageGenerator(
      result: .failure(.requestFailed(status: 503, body: "overloaded"))
    )
    let tool = AgentGenerateImageTool(
      assignment: stubAssignment(),
      generator: generator
    )
    let context = AgentToolContext(workingDirectory: workingDirectory, filesystem: filesystem)
    let args = #"{"prompt": "ok", "output_path": "x.png"}"#
    let result = try await tool.invoke(arguments: Data(args.utf8), context: context)
    XCTAssertTrue(result.isError)
    XCTAssertEqual(result.errorKind, .ioFailure)
    XCTAssertTrue(result.content.contains("503"))
  }

  // MARK: - Registry conditional

  func testToolRegistryOmitsGenerateImageWhenUnassigned() {
    let settings = AgentRuntimeSettings()
    XCTAssertNil(settings.imageAssignment)
    let names = Set(ToolRegistry.tools(for: .develop, settings: settings).map { $0.spec.name })
    XCTAssertFalse(names.contains(AgentGenerateImageTool.toolName))
  }

  func testToolRegistryIncludesGenerateImageWhenAssigned() {
    var settings = AgentRuntimeSettings()
    settings.imageAssignment = stubAssignment()
    let names = Set(ToolRegistry.tools(for: .develop, settings: settings).map { $0.spec.name })
    XCTAssertTrue(names.contains(AgentGenerateImageTool.toolName))
  }

  func testToolRegistryDoesNotExposeGenerateImageInInspectionPhases() {
    var settings = AgentRuntimeSettings()
    settings.imageAssignment = stubAssignment()
    for phase in [AgentPhase.plan, .reflect, .critic] {
      let names = Set(ToolRegistry.tools(for: phase, settings: settings).map { $0.spec.name })
      XCTAssertFalse(
        names.contains(AgentGenerateImageTool.toolName),
        "generate_image leaked into the \(phase) palette")
    }
  }

  // MARK: - Helpers

  private func stubAssignment() -> MediaAssignment {
    MediaAssignment(
      provider: .minimaxToken,
      baseURL: URL(string: "https://api.minimax.io/v1")!,
      apiKey: "k",
      model: "image-01"
    )
  }
}

private final class StubImageGenerator: AgentImageGenerator, @unchecked Sendable {
  enum Outcome {
    case success(Data)
    case failure(AgentImageGenerationError)
  }

  private let lock = NSLock()
  private let outcome: Outcome
  private(set) var recordedPrompts: [String] = []
  private(set) var recordedAssignments: [MediaAssignment] = []

  init(result: Outcome) {
    self.outcome = result
  }

  func generate(prompt: String, assignment: MediaAssignment) async throws -> Data {
    lock.lock()
    recordedPrompts.append(prompt)
    recordedAssignments.append(assignment)
    lock.unlock()
    switch outcome {
    case .success(let data): return data
    case .failure(let error): throw error
    }
  }
}
