import Foundation

package struct PlanTransitionValidationError: LocalizedError, Equatable {
  package enum Reason: Equatable, Sendable {
    case unknown
    case invalidStateMutation
    case noImmediateWork
    case placeholderVerify
    case coverageRequirement
    case weakHandoff
    case ungroundedPaths
    case weakVerifyCoverage
  }

  package var message: String
  package var reason: Reason
  package var missingLabels: [String]
  package var rejectedVerify: String?
  package var rejectedAcceptanceChecks: [String]
  package var vagueAcceptanceChecks: [String]

  package init(
    message: String,
    reason: Reason = .unknown,
    missingLabels: [String] = [],
    rejectedVerify: String? = nil,
    rejectedAcceptanceChecks: [String] = [],
    vagueAcceptanceChecks: [String] = []
  ) {
    self.message = message
    self.reason = reason
    self.missingLabels = missingLabels
    self.rejectedVerify = rejectedVerify
    self.rejectedAcceptanceChecks = rejectedAcceptanceChecks
    self.vagueAcceptanceChecks = vagueAcceptanceChecks
  }

  package var errorDescription: String? {
    message
  }
}

package enum PlanTransitionValidator {
  package static func validate(
    from current: PlanState,
    to next: PlanState,
    forgeProfile: ForgeProfile? = nil,
    repoURL: URL? = nil
  )
    throws
  {
    if !current.actionableCandidates.isEmpty
      && next.actionableCandidates.isEmpty
      && next.completed.count == current.completed.count
    {
      throw PlanTransitionValidationError(
        message:
          "Plan tried to clear all actionable candidates without recording a completion. Refusing to overwrite state.json.",
        reason: .invalidStateMutation
      )
    }

    let droppedBriefFields = droppedBriefFieldLabels(from: current.brief, to: next.brief)
    if !droppedBriefFields.isEmpty {
      throw PlanTransitionValidationError(
        message:
          "Plan tried to drop non-empty brief fields: \(formattedFields(droppedBriefFields)). Keep `brief` stable unless the user explicitly changed the project brief; preserve target users, desired outcomes, constraints, and acceptance signals so Develop keeps the real finish line.\(briefRepairDetail(current.brief))",
        reason: .invalidStateMutation,
        missingLabels: droppedBriefFields
      )
    }

    guard let immediate = next.immediate else {
      let remainingFields =
        remainingPlanFields(in: current, label: "current")
        + remainingPlanFields(in: next, label: "proposed")
      guard remainingFields.isEmpty else {
        throw PlanTransitionValidationError(
          message:
            "Plan returned no immediate work while \(formattedFields(remainingFields)) still contains actionable candidates. Choose one commit-sized Immediate Plan instead; `immediate: null` is only valid when there are no available or active candidates and no useful repo-originated slice.",
          reason: .noImmediateWork
        )
      }
      return
    }
    guard let verify = PlanVerifyCommandPolicy.normalizedCommand(immediate.verify) else {
      throw PlanTransitionValidationError(
        message:
          "Plan returned an empty verify command. Refusing to overwrite state.json.",
        reason: .placeholderVerify,
        missingLabels: ["Verify command"],
        rejectedVerify: nil
      )
    }
    if PlanVerifyCommandPolicy.isPlaceholder(verify) {
      throw PlanTransitionValidationError(
        message:
          "Plan returned placeholder verify command `\(verify)`. Refusing to overwrite state.json.",
        reason: .placeholderVerify,
        missingLabels: ["Verify command"],
        rejectedVerify: verify
      )
    }
    if PlanVerifyCommandPolicy.masksFailures(verify) {
      throw PlanTransitionValidationError(
        message:
          "Plan returned failure-masking verify command `\(verify)`. Verify commands must fail when the check fails; remove fallback no-op clauses such as \(PlanVerifyCommandPolicy.failureMaskingExamples). Refusing to overwrite state.json.",
        reason: .placeholderVerify,
        missingLabels: ["Verify command"],
        rejectedVerify: verify
      )
    }
    if immediate.selectedBecause?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      throw PlanTransitionValidationError(
        message:
          "Plan returned an immediate handoff without `selectedBecause`. Explain why this slice is the right next step so the user can audit planning choice quality.",
        reason: .weakHandoff,
        missingLabels: ["Selection rationale"]
      )
    }
    if immediate.source == nil {
      throw PlanTransitionValidationError(
        message:
          "Plan returned an immediate handoff without `source`. Set `source` to draft, feedback, candidate, focus, repository, or repair so Compass can explain why this work was selected.",
        reason: .weakHandoff,
        missingLabels: ["Selection source"]
      )
    }

    let handoffDigest = PlanHandoffDigest(plan: immediate.plan)
    if let coverageError = ForgeVerifyValidator.coverageViolation(
      verify: verify,
      profile: forgeProfile
    ),
      !isDocumentationOnlyContentVerify(verify, handoffDigest: handoffDigest)
    {
      throw PlanTransitionValidationError(
        message: coverageError,
        reason: .coverageRequirement,
        missingLabels: ["Coverage-ready verify command"],
        rejectedVerify: verify
      )
    }
    guard handoffDigest.status == .ready else {
      let requiredMissing = handoffDigest.missingPieces
        .filter { $0.isRequired }
        .map(\.label)
      let missing =
        requiredMissing.isEmpty
        ? "a concrete Outcome and Acceptance checks"
        : requiredMissing.joined(separator: " and ")
      let rejectedAcceptanceChecks = handoffDigest.commandOnlyAcceptanceChecks
      let vagueAcceptanceChecks = handoffDigest.vagueAcceptanceChecks
      let acceptanceRepairDetail = acceptanceRepairDetail(
        missingLabels: requiredMissing,
        commandOnlyChecks: rejectedAcceptanceChecks,
        vagueChecks: vagueAcceptanceChecks
      )
      throw PlanTransitionValidationError(
        message:
          "Plan returned an immediate handoff that is not executable enough for Develop. Missing \(missing).\(acceptanceRepairDetail) Write `immediate.plan` with short Markdown sections named Outcome and Acceptance checks; include Why it matters when it helps the non-engineer owner. The acceptance checks should state observable finish-line behavior Develop can verify.",
        reason: .weakHandoff,
        missingLabels: requiredMissing,
        rejectedAcceptanceChecks: rejectedAcceptanceChecks,
        vagueAcceptanceChecks: vagueAcceptanceChecks
      )
    }

    if let repoURL {
      try validateGroundedPaths(in: immediate.plan, repoURL: repoURL)
    }
    try validateVerifySupportsHandoff(
      immediate,
      handoffDigest: handoffDigest,
      forgeProfile: forgeProfile
    )
  }

  private static func droppedBriefFieldLabels(
    from current: PlanStrategicContext,
    to next: PlanStrategicContext
  ) -> [String] {
    var labels: [String] = []
    if !current.summary.isEmpty && next.summary.isEmpty {
      labels.append("brief.summary")
    }
    if !current.targetUsers.isEmpty && next.targetUsers.isEmpty {
      labels.append("brief.targetUsers")
    }
    if !current.desiredOutcomes.isEmpty && next.desiredOutcomes.isEmpty {
      labels.append("brief.desiredOutcomes")
    }
    if !current.constraints.isEmpty && next.constraints.isEmpty {
      labels.append("brief.constraints")
    }
    if !current.acceptanceSignals.isEmpty && next.acceptanceSignals.isEmpty {
      labels.append("brief.acceptanceSignals")
    }
    return labels
  }

  private static func remainingPlanFields(in state: PlanState, label: String) -> [String] {
    var fields: [String] = []
    if !state.actionableCandidates.isEmpty {
      fields.append("\(label) candidates")
    }
    return fields
  }

  private static func formattedFields(_ fields: [String]) -> String {
    let uniqueFields = Array(Set(fields)).sorted()
    switch uniqueFields.count {
    case 0:
      return "planning state"
    case 1:
      return uniqueFields[0]
    case 2:
      return "\(uniqueFields[0]) and \(uniqueFields[1])"
    default:
      return uniqueFields.dropLast().joined(separator: ", ")
        + ", and \(uniqueFields.last ?? "planning state")"
    }
  }

  private static func briefRepairDetail(_ brief: PlanStrategicContext) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(brief),
      let json = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return """


      Set `state.brief` exactly to this current brief in the next `plan_submit`:
      ```json
      \(json)
      ```
      """
  }

  private static func formattedRejectedChecks(_ checks: [String]) -> String {
    checks.prefix(3).map { "`\($0)`" }.joined(separator: ", ")
  }

  private static func acceptanceRepairDetail(
    missingLabels: [String],
    commandOnlyChecks: [String],
    vagueChecks: [String]
  ) -> String {
    guard missingLabels.contains("Acceptance checks") else { return "" }

    var details: [String] = []
    if !commandOnlyChecks.isEmpty {
      details.append(
        "Acceptance checks cannot be only verify commands (\(formattedRejectedChecks(commandOnlyChecks))). Put shell commands in `state.immediate.verify`, and describe observable behavior or UI state in `state.immediate.plan`."
      )
    }
    if !vagueChecks.isEmpty {
      details.append(
        "Acceptance checks are too vague (\(formattedRejectedChecks(vagueChecks))). Replace them with specific behavior, UI state, or test-proven signals Develop can verify."
      )
    }

    guard !details.isEmpty else { return "" }
    return " " + details.joined(separator: " ")
  }

  private static func validateGroundedPaths(in plan: String, repoURL: URL) throws {
    let explicitPaths = explicitFilePaths(in: plan)
    let missingPaths = explicitPaths.filter { path in
      guard !isExplicitNewFilePath(path, in: plan) else { return false }
      return !FileManager.default.fileExists(atPath: repoURL.appending(path: path).path)
    }
    guard !missingPaths.isEmpty else { return }

    let details = missingPaths.prefix(4).map { path in
      missingPathDetail(path, repoURL: repoURL)
    }.joined(separator: "\n")
    throw PlanTransitionValidationError(
      message: """
        Plan named file paths that do not exist in the repo:
        \(details)

        Repair the handoff without calling another tool: replace each missing path with an existing path listed above, mark it as `create new file <path>` if it is intentionally new, or remove the unproved path from the Outcome and Acceptance checks.
        """,
      reason: .ungroundedPaths
    )
  }

  private static func validateVerifySupportsHandoff(
    _ immediate: PlanNext,
    handoffDigest: PlanHandoffDigest,
    forgeProfile: ForgeProfile?
  ) throws {
    _ = handoffDigest
    guard forgeProfile == .tesseraApp else { return }
    let normalizedVerify =
      immediate.verify
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if containsRetiredGeneratedProjectTerm(normalizedVerify) {
      throw PlanTransitionValidationError(
        message: """
          Plan selected a retired package-based verify command for a Tessera project:
          `\(immediate.verify)`

          Use `tessera verify . --json` for generated Compass work, or an embedded
          `tessera` tool proof for focused source, test, or entrypoint checks.
          """,
        reason: .weakVerifyCoverage,
        rejectedVerify: immediate.verify
      )
    }

    let plan = immediate.plan.lowercased()
    guard containsRetiredGeneratedProjectTerm(plan) else { return }
    throw PlanTransitionValidationError(
      message: """
        Plan used retired package-based paths for a Tessera project.

        Repair the handoff around Tessera files: `tessera.json`, `src/*.tes`,
        `contexts/*.json`, and `tests/*.json`. Do not target retired manifest,
        package workspace, or old source-file paths for generated Compass work.
        """,
      reason: .weakHandoff
    )
  }

  private static func containsRetiredGeneratedProjectTerm(_ text: String) -> Bool {
    let text = text.lowercased()
    if [
      "package.json",
      "packages/",
      "pnpm",
      "npm-run",
      "nodejs",
      "corepack",
      "typescript",
      "javascript",
      "vitest",
    ].contains(where: { text.contains($0) }) {
      return true
    }

    if text.range(
      of: #"(?:^|[^a-z0-9_-])(?:npm|node|tsc)(?:$|[^a-z0-9_-])"#,
      options: .regularExpression
    ) != nil {
      return true
    }

    return text.range(
      of: #"(?:^|[^a-z0-9_-])[\w./*-]+\.(?:ts|tsx|js|jsx)(?:$|[^a-z0-9])"#,
      options: .regularExpression
    ) != nil
  }

  private static func explicitFilePaths(in text: String) -> [String] {
    let pattern = #"(?:`([^`\n]+\.[A-Za-z0-9]+)`)|((?:[\w.-]+/)+[\w.-]+\.[A-Za-z0-9]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    var seen = Set<String>()
    var paths: [String] = []
    for match in matches {
      let raw: String?
      if match.range(at: 1).location != NSNotFound {
        raw = nsText.substring(with: match.range(at: 1))
      } else if match.range(at: 2).location != NSNotFound {
        raw = nsText.substring(with: match.range(at: 2))
      } else {
        raw = nil
      }
      guard let normalized = normalizePlanPath(raw), seen.insert(normalized).inserted else {
        continue
      }
      paths.append(normalized)
    }
    return paths
  }

  private static func normalizePlanPath(_ raw: String?) -> String? {
    guard var path = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
      return nil
    }
    path = path.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'()[]{}.,:;"))
    while path.hasPrefix("./") {
      path.removeFirst(2)
    }
    guard
      path.contains("/"),
      !path.hasPrefix("/"),
      !path.hasPrefix("../"),
      !path.hasPrefix(".compass/"),
      !path.contains(" "),
      !path.contains("://")
    else {
      return nil
    }
    return path
  }

  private static func isExplicitNewFilePath(_ path: String, in plan: String) -> Bool {
    let loweredPath = path.lowercased()
    let creationPhrases = [
      "create new file",
      "create a new file",
      "add new file",
      "add a new file",
      "write new file",
      "write a new file",
      "introduce new file",
      "introduce a new file",
      "scaffold new file",
      "scaffold a new file",
    ]
    for rawLine in plan.components(separatedBy: "\n") {
      let line = rawLine.lowercased()
      guard line.contains(loweredPath) else { continue }
      if creationPhrases.contains(where: { line.contains($0) }) {
        return true
      }
      if line.contains("create") && line.contains(" file") {
        return true
      }
    }
    return false
  }

  private static func missingPathDetail(_ path: String, repoURL: URL) -> String {
    let requestedURL = repoURL.appending(path: path)
    let nearest = nearestExistingDirectory(from: requestedURL, repoURL: repoURL)
    guard let nearest else { return "- \(path)" }

    var detail = "- \(path) (nearest existing directory: \(relativePath(nearest, repoURL: repoURL))"
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: nearest,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    let names = entries.prefix(6).map { entry in
      let isDirectory =
        ((try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
      return entry.lastPathComponent + (isDirectory ? "/" : "")
    }
    .sorted()
    if !names.isEmpty {
      detail += "; entries: \(names.joined(separator: ", "))"
    }
    let sameFilenameMatches = sameFilenameMatches(for: path, repoURL: repoURL)
    if !sameFilenameMatches.isEmpty {
      detail += "; same filename exists at: \(sameFilenameMatches.joined(separator: ", "))"
    }
    detail += ")"
    return detail
  }

  private static func sameFilenameMatches(
    for path: String,
    repoURL: URL,
    limit: Int = 4
  ) -> [String] {
    let basename = URL(fileURLWithPath: path).lastPathComponent
    guard !basename.isEmpty else { return [] }
    guard
      let enumerator = FileManager.default.enumerator(
        at: repoURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    let skippedDirectories: Set<String> = [
      ".compass",
      ".git",
      ".build",
      "build",
      "target",
    ]
    var matches: [String] = []
    for case let url as URL in enumerator {
      let isDirectory =
        ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
      if isDirectory, skippedDirectories.contains(url.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }
      guard !isDirectory, url.lastPathComponent == basename else { continue }
      matches.append(relativePath(url, repoURL: repoURL))
      if matches.count >= limit { break }
    }
    return matches.sorted()
  }

  private static func nearestExistingDirectory(from url: URL, repoURL: URL) -> URL? {
    let repoPath = repoURL.standardizedFileURL.path
    var candidate = url.deletingLastPathComponent().standardizedFileURL
    while candidate.path.hasPrefix(repoPath) {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        return candidate
      }
      let parent = candidate.deletingLastPathComponent().standardizedFileURL
      if parent.path == candidate.path { break }
      candidate = parent
    }
    return nil
  }

  private static func relativePath(_ url: URL, repoURL: URL) -> String {
    let repoPath = repoURL.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(repoPath) else { return path }
    let suffix = path.dropFirst(repoPath.count).trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))
    return suffix.isEmpty ? "." : String(suffix)
  }

  private static func isDocumentationOnlyContentVerify(
    _ verify: String,
    handoffDigest: PlanHandoffDigest
  ) -> Bool {
    guard isSimpleDocumentationGrepVerify(verify) else { return false }
    let text = ([handoffDigest.outcome ?? ""] + handoffDigest.acceptanceChecks)
      .joined(separator: "\n")
      .lowercased()
    let mentionsDocs =
      text.contains("documentation-only")
      || text.contains("readme")
      || text.contains("docs/")
      || text.contains(".md")
      || text.contains("documentation")
    guard mentionsDocs else { return false }
    return ![
      "contexts/",
      "src/",
      "tessera.json",
      "test file",
      "tests/",
      "source file",
    ].contains { text.contains($0) }
  }

  private static func isSimpleDocumentationGrepVerify(_ verify: String) -> Bool {
    DocumentationGrepVerifyCommand.parse(verify) != nil
  }

}
