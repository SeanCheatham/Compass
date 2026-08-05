public enum ClipboardHelpText {
  public static let runtimeSettings = "Copy a redacted runtime settings note."
  public static let runtimeDiagnostics = "Copy a concise runtime report with workspace readiness."
  public static let projectIntake = "Copy a concise project intake checklist."
  public static let projectVision = "Copy a concise project vision note."
  public static let projectSnapshot =
    "Copy a project snapshot with readiness, recovery, vision, drafts, assumptions, lessons, history, and runtime setup."
  public static let recovery = "Copy a concise recovery note."
  public static let liveTimeline = "Copy a concise Live timeline note."
  public static let liveFailure = "Copy a concise failure note."
  public static let runControl = "Copy a concise run control note."

  /// Help strings currently wired to UI copy affordances.
  public static let allUserFacing: [String] = [
    runtimeSettings,
    runtimeDiagnostics,
    projectIntake,
    projectVision,
    projectSnapshot,
    recovery,
    liveTimeline,
    liveFailure,
    runControl,
  ]
}
