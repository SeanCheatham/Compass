import Foundation

struct LiveFailureInsight: Equatable, Sendable {
  static let detailLimit = 420
  static let identifierLimit = 1_200

  enum Kind: String, Equatable, Sendable {
    case argumentRepair
    case resultContractRepair
    case safetyGate
    case sandboxBoundary
    case editConflict
    case missingFile
    case timeout
    case commandFailure
    case guestBridge
    case unavailableService
    case providerFailure
    case missingResult
    case handoffRepair
    case verifyBypass
    case feedbackRepair
    case unknownTool
    case generic
  }

  var kind: Kind
  var title: String
  var explanation: String
  var nextStep: String
  var badge: String
  var repairOwner: RepairOwner
  var systemImageName: String
  var lineTitle: String
  var detail: String
  var narrationIdentifier: String

  init?(line: LiveLine) {
    guard line.status == .failed || line.level == .error else { return nil }

    let lineTitle = Self.normalized(line.text)
    let detail = Self.normalized(line.detail ?? "")
    let combined = "\(lineTitle)\n\(detail)"
    let normalized = combined.lowercased()

    let presentation = Self.presentation(for: normalized, line: line)
    self.kind = presentation.kind
    self.title = presentation.title
    self.explanation = presentation.explanation
    self.nextStep = presentation.nextStep
    self.badge = presentation.badge
    self.repairOwner = Self.repairOwner(for: presentation.kind)
    self.systemImageName = presentation.systemImageName
    self.lineTitle = StringUtils.boundedText(lineTitle, limit: 160)
    self.detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    self.narrationIdentifier = Self.identifier(
      kind: presentation.kind,
      title: presentation.title,
      explanation: presentation.explanation,
      nextStep: presentation.nextStep,
      repairOwner: repairOwner,
      lineTitle: lineTitle,
      detail: detail
    )
  }

  var allowsNarration: Bool {
    !narrationIdentifier.isEmpty
  }

  struct RepairOwner: Equatable, Sendable {
    static let detailLimit = 180

    var label: String
    var detail: String
    var systemImageName: String
  }

  private static func normalized(_ text: String) -> String {
    StringUtils.boundedText(text, limit: detailLimit)
  }

  private static func presentation(
    for normalized: String,
    line: LiveLine
  ) -> (
    kind: Kind,
    title: String,
    explanation: String,
    nextStep: String,
    badge: String,
    systemImageName: String
  ) {
    if containsAny(normalized, ["unknown tool"]) {
      return (
        .unknownTool,
        "Tool Is Not Available",
        "The agent asked for a tool Compass does not expose in this phase.",
        "Compass will feed that failure back to the agent. If it repeats, the plan may be naming the wrong capability.",
        "Tool palette",
        "wrench.and.screwdriver"
      )
    }

    if containsAny(
      normalized,
      [
        "submit_result missing",
        "ended without submit_result",
        "model stopped without calling submit_result",
        "agent exceeded max iterations",
        "agent exceeded wall-clock timeout",
      ])
    {
      return (
        .missingResult,
        "Agent Did Not Hand Back A Result",
        "The model ended its turn without the result tool Compass needs to safely finish this phase.",
        "Compass will ask for the same answer again as a `submit_result` call instead of accepting prose.",
        "Result handoff",
        "arrow.uturn.backward.circle"
      )
    }

    if containsAny(
      normalized,
      [
        "submit_result verify bypass rejected", "bypassverify=true", "bypassverify: true",
      ]
    ) {
      return (
        .verifyBypass,
        "Verify Bypass Needs A Reason",
        "Develop tried to skip the verification command without proving the command itself is wrong or impossible.",
        "The next attempt should run verification, or explain the exact verify-command problem and leave a repair for Plan.",
        "Verify gate",
        "checkmark.seal"
      )
    }

    if containsAny(
      normalized,
      [
        "submit_result plan rejected", "placeholder verify command",
        "failure-masking verify command", "command-only acceptance checks",
        "vague acceptance checks", "missing acceptance checks",
        "forge profile coverage requirement",
      ]
    ) {
      return (
        .handoffRepair,
        "Plan Needs A Clearer Handoff",
        "Compass rejected the Immediate Work because Develop would not have a safe, observable finish line.",
        "Plan should return one concrete outcome, a real verify command, and acceptance checks a non-engineer can recognize.",
        "Finish line",
        "target"
      )
    }

    if containsAny(
      normalized,
      [
        "submit_result feedback rejected", "submit_result critic feedback rejected",
        "too weak to hand", "without actionable", "weak handoff",
      ]
    ) {
      return (
        .feedbackRepair,
        "Follow-Up Feedback Was Too Vague",
        "Compass rejected the handoff because the next Plan pass would not know the smallest concrete repair.",
        "The next attempt should name the exact blocker, failed proof, or punch-list item before handing control back.",
        "Next repair",
        "text.bubble"
      )
    }

    if containsAny(
      normalized,
      [
        "submit_result contract rejected",
        "wrong type at `state.",
        "missing required field `state.",
        "planrunresult requires",
      ]
    ) {
      return (
        .resultContractRepair,
        "Result Shape Needs Repair",
        "Compass received a `submit_result` call, but one of the result fields did not match the phase contract.",
        "The agent should resend the same result with the exact required field types, especially object-vs-string and array-vs-string fields.",
        "Schema",
        "curlybraces"
      )
    }

    if containsAny(normalized, ["has not been read", "would overwrite"]) {
      return (
        .safetyGate,
        "File Safety Gate Stopped It",
        "Compass blocked an overwrite because the agent had not read the current file contents in this session.",
        "The next attempt should read the file first, then retry the smallest exact edit.",
        "Protected",
        "shield.checkered"
      )
    }

    if containsAny(normalized, ["escapes", "outside the working directory", "path escape"]) {
      return (
        .sandboxBoundary,
        "Workspace Boundary Blocked It",
        "Compass refused a path outside the project workspace so the run cannot touch unrelated files.",
        "The agent should retry with a project-relative path or explain why the requested file is out of scope.",
        "Sandbox",
        "lock.shield"
      )
    }

    if containsAny(normalized, ["oldstring not found", "edit conflict", "old string not found"]) {
      return (
        .editConflict,
        "Edit Did Not Match",
        "The exact text the agent wanted to replace was not found, usually because the file changed or the snippet was too broad.",
        "The next attempt should reread the file and apply a narrower edit against the current text.",
        "Reread",
        "doc.text.magnifyingglass"
      )
    }

    if containsAny(normalized, ["file not found", "no such file", "no codemap entry"]) {
      return (
        .missingFile,
        "File Was Not Found",
        "The agent looked for a file or index entry Compass cannot currently see.",
        "The next attempt should list files, refresh the codemap if needed, or choose the current path.",
        "Find path",
        "questionmark.folder"
      )
    }

    if containsAny(
      normalized,
      [
        "chat completions stream failed",
        "rate limit",
        "unauthorized",
        "forbidden",
        "invalid api key",
        "status code: 401",
        "status code: 403",
        "status code: 429",
        "network connection lost",
        "cannot connect to host",
        "not connected to internet",
      ]
    ) {
      return (
        .providerFailure,
        "Model Provider Needs Attention",
        "The selected Text provider failed before Compass could receive a complete model response.",
        "Check the selected model, endpoint, API key, and network connection before retrying the same phase.",
        "Provider",
        "antenna.radiowaves.left.and.right"
      )
    }

    if containsAny(normalized, ["timed out", "timeout", "wall-clock"]) {
      return (
        .timeout,
        "Step Ran Out Of Time",
        "A command or agent step exceeded its time budget before it could finish cleanly.",
        "The next attempt should narrow the command, raise the explicit timeout only when justified, or split the work.",
        "Time budget",
        "timer"
      )
    }

    if containsAny(normalized, ["guest rpc", "vsock", "transport", "guest internal error"]) {
      return (
        .guestBridge,
        "Private Workspace Connection Had Trouble",
        "Compass had trouble talking to the private workspace that runs agent commands.",
        "Retry after the private workspace is ready; if it repeats, repair or restart the workspace.",
        "Workspace",
        "network"
      )
    }

    if containsAny(normalized, ["compass-engine not found", "could not locate compass-engine"]) {
      return (
        .unavailableService,
        "Rust Engine Is Not Installed",
        "Compass could not find the Rust sidecar that provides structured Cargo tooling.",
        "Build or install `compass-engine`, then rerun the Rust tool or repair the Shared VM provisioning.",
        "Rust engine",
        "shippingbox"
      )
    }

    if containsAny(normalized, ["missing-cargo-llvm-cov", "cargo-llvm-cov is not installed"]) {
      return (
        .commandFailure,
        "Rust Coverage Tool Is Missing",
        "The Rust coverage probe needs cargo-llvm-cov, but it is not installed or could not run.",
        "Install `cargo-llvm-cov`, then rerun `coverage_gaps` or the planned Rust verify command.",
        "Coverage",
        "gauge.with.dots.needle.bottom.50percent"
      )
    }

    if containsAny(
      normalized,
      [
        "generated-scaffold-missing-member",
        "generated-scaffold-metadata-drift",
        "scaffold-check: fail",
      ]
    ) {
      return (
        .commandFailure,
        "Rust Scaffold Drift Detected",
        "The generated Rust project no longer matches the Compass scaffold contract.",
        "Use `scaffold_check`, restore the missing scaffold file or member, then rerun the structured Rust probe.",
        "Scaffold",
        "wrench.and.screwdriver"
      )
    }

    if normalized.contains("clippy::") {
      return (
        .commandFailure,
        "Clippy Lint Failure",
        "Rust linting found an issue that should be fixed before the proof passes.",
        "Use the clippy diagnostic location, make the smallest code change, then rerun `clippy_lint` or verify.",
        "Clippy",
        "paintbrush.pointed"
      )
    }

    if normalized.contains("error[e0") {
      return (
        .commandFailure,
        "Rust Compile Error",
        "rustc reported a compile error with a stable error code.",
        "Start at the reported file and line, fix the first compiler error, then rerun `cargo_check`.",
        "Rustc",
        "curlybraces"
      )
    }

    if normalized.contains("could not compile `") {
      return (
        .commandFailure,
        "Rust Crate Did Not Compile",
        "Cargo identified a crate that failed to compile.",
        "Use the diagnostic immediately above the crate failure, fix that crate first, then rerun the scoped Cargo proof.",
        "Cargo",
        "terminal"
      )
    }

    if containsAny(normalized, ["not enabled", "not available", "unavailable"]) {
      return (
        .unavailableService,
        "Required Service Is Unavailable",
        "The agent requested a capability that is not enabled or ready for this project route.",
        "Check the related settings or let the next plan choose a route that is available.",
        "Unavailable",
        "exclamationmark.icloud"
      )
    }

    if containsAny(
      normalized,
      [
        "invalid arguments",
        "failed to decode arguments",
        "had undecodable args",
        "tool call decode",
        "args are not valid json",
        "missing required field",
        "expected ",
      ]
    ) {
      return (
        .argumentRepair,
        "Tool Request Needs Repair",
        "Compass could not understand the tool arguments, so it rejected the call before trusting the result.",
        "The agent should retry the same intent with the tool's required fields and smaller JSON if needed.",
        "Schema",
        "curlybraces"
      )
    }

    if line.kind == .command || containsAny(normalized, ["[exit ", "bash command failed"]) {
      return (
        .commandFailure,
        "Command Reported A Failure",
        "A command finished with a failing result; Compass preserved the output as the concrete symptom.",
        "Use the first clear error in the output as the next fix target, then rerun the proof.",
        "Command",
        "terminal"
      )
    }

    return (
      .generic,
      "Run Step Needs Review",
      "This live event failed, and Compass kept the detail so the next attempt does not have to guess.",
      "Start from the preserved detail, fix the smallest concrete cause, and rerun the relevant proof.",
      "Review",
      "exclamationmark.triangle"
    )
  }

  private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
    needles.contains { haystack.contains($0) }
  }

  private static func repairOwner(for kind: Kind) -> RepairOwner {
    switch kind {
    case .handoffRepair:
      return owner(
        label: "Plan handoff",
        detail: "Plan should return a smaller executable handoff before Develop retries.",
        systemImageName: "map"
      )
    case .providerFailure:
      return owner(
        label: "Text provider",
        detail: "Check the selected model, endpoint, API key, and network connection.",
        systemImageName: "text.bubble.badge.exclamationmark"
      )
    case .guestBridge:
      return owner(
        label: "Private workspace",
        detail: "Repair or restart the private workspace before retrying.",
        systemImageName: "network"
      )
    case .unavailableService:
      return owner(
        label: "Capability setting",
        detail: "Check the related setting or choose a path that is available.",
        systemImageName: "exclamationmark.icloud"
      )
    case .commandFailure:
      return owner(
        label: "Project proof",
        detail: "Fix the first clear command error, then rerun the proof.",
        systemImageName: "terminal"
      )
    case .timeout:
      return owner(
        label: "Scope or time",
        detail: "Narrow the command or split the work before increasing a timeout.",
        systemImageName: "timer"
      )
    case .safetyGate, .sandboxBoundary, .editConflict, .missingFile:
      return owner(
        label: "Workspace edit",
        detail: "Reread or list the current workspace, then retry the smallest exact edit.",
        systemImageName: "doc.text.magnifyingglass"
      )
    case .argumentRepair, .resultContractRepair, .missingResult, .verifyBypass, .feedbackRepair,
      .unknownTool:
      return owner(
        label: "Agent handoff",
        detail: "Ask the agent to resend the required tool, result, or feedback shape.",
        systemImageName: "arrow.uturn.backward.circle"
      )
    case .generic:
      return owner(
        label: "Review needed",
        detail: "Use the preserved live detail to choose the smallest concrete repair.",
        systemImageName: "exclamationmark.triangle"
      )
    }
  }

  private static func owner(
    label: String,
    detail: String,
    systemImageName: String
  ) -> RepairOwner {
    RepairOwner(
      label: label,
      detail: StringUtils.boundedText(detail, limit: RepairOwner.detailLimit),
      systemImageName: systemImageName
    )
  }

  private static func identifier(
    kind: Kind,
    title: String,
    explanation: String,
    nextStep: String,
    repairOwner: RepairOwner,
    lineTitle: String,
    detail: String
  ) -> String {
    let raw = [
      "kind:\(kind.rawValue)",
      "title:\(title)",
      "explanation:\(explanation)",
      "next:\(nextStep)",
      "owner:\(repairOwner.label):\(repairOwner.detail)",
      "line:\(StringUtils.boundedText(lineTitle, limit: 160))",
      "detail:\(StringUtils.boundedText(detail, limit: detailLimit))",
    ].joined(separator: "|")
    return StringUtils.boundedText(raw, limit: identifierLimit)
  }
}

struct LiveFailureInsightNarration: Equatable, Sendable {
  var insightIdentifier: String
  var text: String
}

struct LiveFailureInsightClipboardPayload: Equatable, Sendable {
  static let textLimit = 2_600

  var text: String

  init(insight: LiveFailureInsight) {
    let sections = [
      "Compass Live Failure Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded failure context. Do not invent files, commands, "
        + "credentials, project facts, outcomes, or extra scope.",
      "- Start from the raw live row and detail, then apply the safe next step.",
      "- If the repair requires missing user input, ask for it instead of guessing.",
      "",
      "Failure type: \(insight.title)",
      "Category: \(insight.kind.rawValue)",
      "Badge: \(insight.badge)",
      "Repair owner: \(insight.repairOwner.label) - \(insight.repairOwner.detail)",
      "",
      "Plain explanation:",
      insight.explanation,
      "",
      "Safe next step:",
      insight.nextStep,
      "",
      "Raw live row:",
      insight.lineTitle.isEmpty ? "No live row title captured." : insight.lineTitle,
      "",
      "Raw detail:",
      insight.detail.isEmpty ? "No detail captured." : insight.detail,
    ]

    text = LiveFailureInsightClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum LiveFailureInsightClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

enum LiveFailureInsightNarrator {
  static let maxCharacters = 340

  static func narrate(insight: LiveFailureInsight) async -> LiveFailureInsightNarration? {
    guard insight.allowsNarration else { return nil }
    guard FoundationModelsAvailability.isAvailable else { return nil }

    if #available(macOS 26.0, *) {
      guard
        let generated = await FoundationModelsAvailability._streamText(
          prompt: prompt(for: insight)
        )
      else {
        return nil
      }
      let text = sanitized(generated)
      guard !text.isEmpty else { return nil }
      return LiveFailureInsightNarration(
        insightIdentifier: insight.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for insight: LiveFailureInsight) -> String {
    """
    You are Compass explaining one failed live event to a non-engineer.
    Use only the facts below. Do not invent project facts, files, commands, outcomes, or promises.
    Return one calm sentence under 45 words. No Markdown.

    Failure type: \(insight.title)
    Plain explanation: \(insight.explanation)
    Repair owner: \(insight.repairOwner.label) - \(insight.repairOwner.detail)
    Safe next step: \(insight.nextStep)
    Raw live row: \(insight.lineTitle)
    Raw detail: \(insight.detail)
    """
  }

  private static func sanitized(_ text: String) -> String {
    let normalized = StringUtils.boundedText(
      text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " "),
      limit: maxCharacters
    )
    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))

    let lowercased = normalized.lowercased()
    guard
      !normalized.contains("{"),
      !normalized.contains("}"),
      !normalized.contains("```"),
      !normalized.hasPrefix("-"),
      !lowercased.contains("http://"),
      !lowercased.contains("https://"),
      !PrivateWorkspaceCopy.containsImplementationTerm(normalized)
    else {
      return ""
    }
    return normalized
  }
}
