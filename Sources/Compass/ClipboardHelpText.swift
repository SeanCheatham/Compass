enum ClipboardHelpText {
  static let setup = "Copy a concise setup note."
  static let privateWorkspaceReadiness = "Copy a concise private workspace status note."
  static let runtimeSettings = "Copy a redacted runtime settings note."
  static let factoryRouting = "Copy a concise factory routing note."
  static let runtimeDiagnostics = "Copy a concise runtime report with workspace readiness."
  static let projectIntake = "Copy a concise project intake checklist."
  static let projectVision = "Copy a concise project vision note."
  static let projectLessons = "Copy a concise project lessons note."
  static let projectSnapshot =
    "Copy a project snapshot with readiness, recovery, vision, drafts, assumptions, lessons, history, and runtime setup."
  static let recovery = "Copy a concise recovery note."
  static let liveTimeline = "Copy a concise Live timeline note."
  static let liveFailure = "Copy a concise failure note."
  static let runControl = "Copy a concise run control note."
  static let assumptions = "Copy a concise assumptions note."
  static let draftQueue = "Copy a concise draft queue note."
  static let runHistory = "Copy a concise run history note."
  static let factoryBrief = "Copy a concise factory brief."
  static let immediateWork = "Copy a concise Immediate Work note."
  static let planRepair = "Copy a focused Plan repair note."
  static let worldAtlas = "Copy a concise World Atlas note."

  static let allUserFacing: [String] = [
    setup,
    privateWorkspaceReadiness,
    runtimeSettings,
    factoryRouting,
    runtimeDiagnostics,
    projectIntake,
    projectVision,
    projectLessons,
    projectSnapshot,
    recovery,
    liveTimeline,
    liveFailure,
    runControl,
    assumptions,
    draftQueue,
    runHistory,
    factoryBrief,
    immediateWork,
    planRepair,
    worldAtlas,
  ]
}
