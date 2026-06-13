package enum ClipboardHelpText {
  package static let setup = "Copy a concise setup note."
  package static let runtimeReadiness = "Copy a concise container runtime status note."
  package static let runtimeSettings = "Copy a redacted runtime settings note."
  package static let tournamentRouting = "Copy a concise factory routing note."
  package static let runtimeDiagnostics = "Copy a concise runtime report with workspace readiness."
  package static let projectIntake = "Copy a concise project intake checklist."
  package static let projectVision = "Copy a concise project vision note."
  package static let projectLessons = "Copy a concise project lessons note."
  package static let projectSnapshot =
    "Copy a project snapshot with readiness, recovery, vision, drafts, assumptions, lessons, history, and runtime setup."
  package static let recovery = "Copy a concise recovery note."
  package static let liveTimeline = "Copy a concise Live timeline note."
  package static let liveFailure = "Copy a concise failure note."
  package static let runControl = "Copy a concise run control note."
  package static let assumptions = "Copy a concise assumptions note."
  package static let draftQueue = "Copy a concise draft queue note."
  package static let runHistory = "Copy a concise run history note."
  package static let tournamentBrief = "Copy a concise factory brief."
  package static let immediateWork = "Copy a concise Immediate Work note."
  package static let planRepair = "Copy a focused Plan repair note."

  package static let allUserFacing: [String] = [
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
