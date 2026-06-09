import Foundation

enum ToolRegistry {
  static func readOnlyTools() -> [AgentTool] {
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

  static func developTools() -> [AgentTool] {
    readOnlyTools() + [
      AgentWriteFileTool(),
      AgentEditFileTool(),
      AgentBashTool(),
    ]
  }

  static func inspectionTools() -> [AgentTool] {
    readOnlyTools() + [AgentBashTool()]
  }

  static func tools(
    for phase: AgentPhase,
    settings: AgentRuntimeSettings,
    toolchainService: (any SharedVMToolchainService)? = nil
  ) -> [AgentTool] {
    var tools: [AgentTool]
    switch phase {
    case .plan:
      tools = inspectionTools() + [AgentPlanHistoryTool()]
    case .critic:
      tools = inspectionTools()
    case .develop:
      tools = developTools()
    }
    if toolchainService != nil {
      tools.append(AgentListToolchainsTool())
      tools.append(AgentInstallToolchainTool())
    }
    _ = settings
    return tools
  }

  static func tools(for phase: AgentPhase) -> [AgentTool] {
    tools(for: phase, settings: AgentRuntimeSettings())
  }

  static func tools(for phase: AgentPhase, settings: AgentRuntimeSettings) -> [AgentTool] {
    tools(for: phase, settings: settings, toolchainService: nil)
  }
}
