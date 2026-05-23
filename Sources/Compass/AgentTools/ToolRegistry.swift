import Foundation

/// Phase-specific tool sets handed to `AgentExecutor`.
///
/// All four agent phases share a common read-only inspection core
/// (file/code reads, codemap lookups, delegation). Develop additionally
/// gets file mutation + shell. Plan/Reflect/Critic additionally get
/// `bash` so they can probe the project (build, test, lint, git) without
/// touching tracked files — the system prompt is what keeps them from
/// running mutating commands; bash itself can't enforce intent.
enum ToolRegistry {
  /// Read-only file access + codemap-backed structural lookups + delegate.
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
    ]
  }

  /// Read-only set plus write/edit/bash. The Develop phase.
  static func developTools() -> [AgentTool] {
    readOnlyTools() + [
      AgentWriteFileTool(),
      AgentEditFileTool(),
      AgentBashTool(),
    ]
  }

  /// Read-only set plus `bash`. Plan/Reflect/Critic — phases that need to
  /// probe the project (build, test, lint, git history) but must not
  /// mutate tracked files.
  static func inspectionTools() -> [AgentTool] {
    readOnlyTools() + [
      AgentBashTool()
    ]
  }

  static func tools(for phase: AgentPhase) -> [AgentTool] {
    switch phase {
    case .plan, .reflect, .critic: return inspectionTools()
    case .develop: return developTools()
    }
  }
}
