import Testing

@testable import Compass

struct AgentDelegateRustProfileTests {
  @Test func rustClippyProfileDoesNotExposeWriteFile() throws {
    let names = AgentExecutorDelegateRunner.toolNames(forProfile: "rust-clippy")

    #expect(names?.contains(AgentClippyLintTool.toolName) == true)
    #expect(names?.contains(AgentWriteFileTool.toolName) == false)
    #expect(names?.contains(AgentEditFileTool.toolName) == false)
    #expect(names?.contains(AgentVisualVerifyTool.toolName) == false)
  }

  @Test func rustTestProfileIncludesCargoCheckAndCargoTest() throws {
    let names = AgentExecutorDelegateRunner.toolNames(forProfile: "rust-test")

    #expect(names?.contains(AgentCargoCheckTool.toolName) == true)
    #expect(names?.contains(AgentCargoTestTool.toolName) == true)
    #expect(names?.contains(AgentWriteFileTool.toolName) == false)
    #expect(names?.contains(AgentEditFileTool.toolName) == false)
    #expect(names?.contains(AgentVisualVerifyTool.toolName) == false)
  }
}
