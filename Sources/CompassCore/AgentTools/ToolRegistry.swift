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
    promptMode: AgentPromptMode = .envelope
  ) -> [AgentTool] {
    switch phase {
    case .plan:
      return inspectionTools() + [AgentPlanHistoryTool()]
    case .critic:
      return inspectionTools()
    case .develop:
      return developTools(promptMode: promptMode)
    }
  }
}
