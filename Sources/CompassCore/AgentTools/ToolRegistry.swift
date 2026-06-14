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

  package static func tesseraReadOnlyTools(includePlanHistory: Bool = false) -> [AgentTool] {
    var tools: [AgentTool] = [
      AgentTesseraTool(allowsMutation: false),
      AgentOutlineTool(),
      AgentFindSymbolTool(),
      AgentSummaryTool(),
      AgentListFilesTool(),
      AgentImportersOfTool(),
      AgentDelegateTool(),
      AgentRecordAssumptionTool(),
      AgentRemoveAssumptionTool(),
    ]
    if includePlanHistory {
      tools.append(AgentPlanHistoryTool())
    }
    return tools
  }

  package static func tesseraDevelopTools() -> [AgentTool] {
    [
      AgentTesseraTool(allowsMutation: true),
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
    settings: AgentRuntimeSettings,
    forgeProfile: ForgeProfile? = nil
  ) -> [AgentTool] {
    if forgeProfile == .tesseraApp {
      switch phase {
      case .plan:
        return tesseraReadOnlyTools(includePlanHistory: true)
      case .critic:
        return tesseraReadOnlyTools()
      case .develop:
        return tesseraDevelopTools()
      }
    }

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

  package static func tools(for phase: AgentPhase, forgeProfile: ForgeProfile?) -> [AgentTool] {
    tools(for: phase, settings: AgentRuntimeSettings(), forgeProfile: forgeProfile)
  }
}
