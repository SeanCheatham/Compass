import Foundation

/// Phase-specific tool sets handed to `AgentExecutor`.
///
/// All four agent phases share a common read-only inspection core
/// (file/code reads, codemap lookups, delegation). Develop additionally
/// gets file mutation + shell. Plan/Reflect/Critic additionally get
/// `bash` so they can probe the project (build, test, lint, git) without
/// touching tracked files — the system prompt is what keeps them from
/// running mutating commands; bash itself can't enforce intent.
///
/// Media-generation tools are conditional: the user-configured
/// per-capability assignments on `AgentRuntimeSettings` decide whether
/// the agent sees `generate_image` (and, eventually, audio/video
/// siblings). When a capability is unassigned, the tool is absent
/// from the palette — the model can't accidentally call something
/// the user hasn't wired up.
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

  /// Phase tools assembled with the user's per-capability provider
  /// assignments folded in. Media tools land in the Develop phase
  /// only — Plan/Reflect/Critic are inspection passes that shouldn't
  /// be producing artifacts.
  static func tools(for phase: AgentPhase, settings: AgentRuntimeSettings) -> [AgentTool] {
    switch phase {
    case .plan, .reflect, .critic:
      return inspectionTools()
    case .develop:
      var tools = developTools()
      if let imageAssignment = settings.imageAssignment {
        tools.append(AgentGenerateImageTool(assignment: imageAssignment))
      }
      return tools
    }
  }

  /// Convenience overload for callers (tests, structural checks)
  /// that only care about the phase's baseline tool set and have
  /// no media assignments to inject.
  static func tools(for phase: AgentPhase) -> [AgentTool] {
    tools(for: phase, settings: AgentRuntimeSettings())
  }
}
