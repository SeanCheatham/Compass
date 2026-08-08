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

  public static func healthTools(
    focus: HealthFocus = .bugHunt,
    promptMode: AgentPromptMode = .envelope
  ) -> [AgentTool] {
    switch focus {
    case .bugHunt:
      return readOnlyTools() + [
        AgentWriteGeneratedTestTool(),
        AgentBashTool(),
      ]
    case .test, .docs, .cleanup:
      return readOnlyTools() + [
        AgentHealthScopedWriteFileTool(focus: focus),
        AgentHealthScopedEditFileTool(focus: focus, promptMode: promptMode),
        AgentBashTool(),
      ]
    }
  }

  public static func tools(
    for phase: AgentPhase,
    promptMode: AgentPromptMode = .envelope,
    healthFocus: HealthFocus = .bugHunt
  ) -> [AgentTool] {
    switch phase {
    case .plan:
      return inspectionTools() + [AgentPlanHistoryTool()]
    case .critic, .requirementsAudit:
      return inspectionTools()
    case .develop:
      return developTools(promptMode: promptMode)
    case .health:
      return healthTools(focus: healthFocus, promptMode: promptMode)
    }
  }
}
