import Foundation

public enum ToolRegistry {
  public static func readOnlyTools() -> [AgentTool] {
    [
      AgentReadFileTool(),
      AgentLsTool(),
      AgentGrepTool(),
      AgentGlobTool(),
      AgentOutlineTool(),
      AgentFindSymbolTool(),
      AgentSummaryTool(),
      AgentListFilesTool(),
      AgentImportersOfTool(),
      AgentDelegateTool(),
      AgentRecordAssumptionTool(),
      AgentRemoveAssumptionTool(),
    ]
  }

  public static func developTools(promptMode: AgentPromptMode = .envelope) -> [AgentTool] {
    let editTool: any AgentTool =
      promptMode == .nativeTools ? AgentEditFileTextTool() : AgentEditFileTool()
    return readOnlyTools() + [
      AgentWriteFileTool(),
      editTool,
      AgentBashTool(),
    ]
  }

  public static func inspectionTools() -> [AgentTool] {
    readOnlyTools() + [AgentBashTool()]
  }

  public static func tools(
    for phase: AgentPhase,
    settings: AgentRuntimeSettings,
    promptMode: AgentPromptMode = .envelope
  ) -> [AgentTool] {
    let tools: [AgentTool]
    switch phase {
    case .plan:
      tools = inspectionTools() + [AgentPlanHistoryTool()]
    case .critic:
      tools = inspectionTools()
    case .develop:
      tools = developTools(promptMode: promptMode)
    }
    _ = settings
    return tools
  }

  public static func tools(for phase: AgentPhase) -> [AgentTool] {
    tools(for: phase, settings: AgentRuntimeSettings())
  }
}
