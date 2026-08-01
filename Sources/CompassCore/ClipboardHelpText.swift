public enum ClipboardHelpText {
  public static let setup = "Copy a concise setup note."
  public static let runtimeReadiness = "Copy a concise container runtime status note."
  public static let runtimeSettings = "Copy a redacted runtime settings note."
  public static let tournamentRouting = "Copy a concise factory routing note."
  public static let runtimeDiagnostics = "Copy a concise runtime report with workspace readiness."
  public static let projectIntake = "Copy a concise project intake checklist."
  public static let projectVision = "Copy a concise project vision note."
  public static let projectLessons = "Copy a concise project lessons note."
  public static let projectSnapshot =
    "Copy a project snapshot with readiness, recovery, vision, drafts, assumptions, lessons, history, and runtime setup."
  public static let recovery = "Copy a concise recovery note."
  public static let liveTimeline = "Copy a concise Live timeline note."
  public static let liveFailure = "Copy a concise failure note."
  public static let runControl = "Copy a concise run control note."
  public static let assumptions = "Copy a concise assumptions note."
  public static let draftQueue = "Copy a concise draft queue note."
  public static let runHistory = "Copy a concise run history note."
  public static let tournamentBrief = "Copy a concise factory brief."
  public static let immediateWork = "Copy a concise Immediate Work note."
  public static let planRepair = "Copy a focused Plan repair note."

  public static let allUserFacing: [String] = [
    setup,
    runtimeReadiness,
    runtimeSettings,
    tournamentRouting,
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
    tournamentBrief,
    immediateWork,
    planRepair,
  ]
}
