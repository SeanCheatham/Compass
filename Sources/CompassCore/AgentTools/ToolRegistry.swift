import Foundation

package enum ToolRegistry {
  package static func readOnlyTools() -> [AgentTool] {
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
      AgentTesseraTool(),
      AgentDelegateTool(),
      AgentRecordAssumptionTool(),
      AgentRemoveAssumptionTool(),
    ]
  }

  package static func developTools() -> [AgentTool] {
    readOnlyTools() + [
      AgentWriteFileTool(),
      AgentEditFileTool(),
      AgentBashTool(),
    ]
  }

  package static func inspectionTools() -> [AgentTool] {
    readOnlyTools() + [AgentBashTool()]
  }

  package static func tools(
    for phase: AgentPhase,
    settings: AgentRuntimeSettings
  ) -> [AgentTool] {
    let tools: [AgentTool]
    switch phase {
    case .plan:
      tools = inspectionTools() + [AgentPlanHistoryTool()]
    case .critic:
      tools = inspectionTools()
    case .develop:
      tools = developTools()
    }
    _ = settings
    return tools
  }

  package static func tools(for phase: AgentPhase) -> [AgentTool] {
    tools(for: phase, settings: AgentRuntimeSettings())
  }
}
