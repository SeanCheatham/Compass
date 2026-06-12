import Foundation

struct PlanTransitionValidationError: LocalizedError, Equatable {
  enum Reason: Equatable, Sendable {
    case unknown
    case invalidStateMutation
    case noImmediateWork
    case placeholderVerify
    case coverageRequirement
    case weakHandoff
    case ungroundedPaths
    case weakVerifyCoverage
  }

  var message: String
  var reason: Reason
  var missingLabels: [String]
  var rejectedVerify: String?
  var rejectedAcceptanceChecks: [String]
  var vagueAcceptanceChecks: [String]

  init(
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

  var errorDescription: String? {
    message
  }
}

enum PlanTransitionValidator {
  static func validate(
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
    try validateVerifySupportsHandoff(immediate, handoffDigest: handoffDigest)
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
    let suspiciousNewPaths = explicitPaths.compactMap { path -> String? in
      guard isExplicitNewFilePath(path, in: plan),
        !FileManager.default.fileExists(atPath: repoURL.appending(path: path).path),
        let conflict = packageEntryPointConflict(forNewPath: path, repoURL: repoURL),
        !planExplicitlyMovesEntryPoint(to: path, conflict: conflict, in: plan)
      else {
        return nil
      }
      return suspiciousNewFileDetail(path, conflict: conflict)
    }
    guard suspiciousNewPaths.isEmpty else {
      let details = suspiciousNewPaths.prefix(4).joined(separator: "\n")
      let repairs = explicitPaths.compactMap { path -> String? in
        guard isExplicitNewFilePath(path, in: plan),
          !FileManager.default.fileExists(atPath: repoURL.appending(path: path).path),
          let conflict = packageEntryPointConflict(forNewPath: path, repoURL: repoURL),
          !planExplicitlyMovesEntryPoint(to: path, conflict: conflict, in: plan)
        else {
          return nil
        }
        return
          "- Replace `\(path)` with `\(conflict.declaredPath)` in the Outcome and Acceptance checks."
      }.prefix(4).joined(separator: "\n")
      throw PlanTransitionValidationError(
        message: """
          Plan marked new file paths that look like duplicate package entry points:
          \(details)

          Repair the handoff by targeting the existing entry point:
          \(repairs)

          Do not resubmit the same new-file path. Do not add a second package.json entry for the same CLI. If the new file truly must replace the existing entry point, explicitly say to change the listed package.json field from the existing path to the new path and explain why.
          """,
        reason: .ungroundedPaths
      )
    }

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

        Use read_file/list_files/glob before naming an existing target path. If the packet really needs a new file, say `create new file <path>` in the Outcome or Acceptance checks so Develop knows to use write_file.
        """,
      reason: .ungroundedPaths
    )
  }

  private static func validateVerifySupportsHandoff(
    _ immediate: PlanNext,
    handoffDigest: PlanHandoffDigest
  ) throws {
    let normalizedVerify =
      immediate.verify
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let plan = immediate.plan.lowercased()
    let acceptanceText = ([handoffDigest.outcome ?? ""] + handoffDigest.acceptanceChecks)
      .joined(separator: "\n")
      .lowercased()
    if isFocusedCoverageVerify(normalizedVerify),
      claimsNewCLIBehavior(acceptanceText),
      claimsCLIImplementationWork(plan + "\n" + acceptanceText)
    {
      throw PlanTransitionValidationError(
        message: """
          Plan selected test-only verify command `\(immediate.verify)` for new CLI implementation work.

          `pnpm test -- --coverage` is only acceptable for focused test-only slices. This handoff asks Develop to implement CLI behavior, so use `pnpm verify` and keep the CLI test update in the acceptance checks.
          """,
        reason: .weakVerifyCoverage,
        rejectedVerify: immediate.verify
      )
    }
    guard normalizedVerify == "pnpm verify" || normalizedVerify == "pnpm run verify" else {
      return
    }
    guard claimsNewCLIBehavior(acceptanceText), !mentionsTestProof(plan) else {
      return
    }

    throw PlanTransitionValidationError(
      message: """
        Plan selected generic `\(immediate.verify)` for new CLI behavior, but the handoff does not include a CLI test or direct proof.

        `pnpm verify` only proves this packet if Develop also adds or updates a test for the claimed CLI behavior, such as `packages/cli/src/main.test.ts`. Add the test file/update to the handoff, or choose a focused verify command that directly exercises the CLI output.
        """,
      reason: .weakVerifyCoverage,
      rejectedVerify: immediate.verify
    )
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
    detail += ")"
    return detail
  }

  private struct PackageEntryPointConflict {
    let manifestPath: String
    let declaredPath: String
    let field: String
  }

  private static func packageEntryPointConflict(forNewPath path: String, repoURL: URL)
    -> PackageEntryPointConflict?
  {
    guard isEntryPointAlias(path) else { return nil }
    let targetURL = repoURL.appending(path: path).standardizedFileURL
    guard
      let packageDirectory = nearestPackageDirectory(
        from: targetURL.deletingLastPathComponent(),
        repoURL: repoURL
      ),
      let entryPoints = packageEntryPoints(in: packageDirectory)
    else {
      return nil
    }

    for entryPoint in entryPoints {
      let entryURL = packageDirectory.appending(path: entryPoint.path).standardizedFileURL
      guard entryURL.path != targetURL.path,
        FileManager.default.fileExists(atPath: entryURL.path)
      else {
        continue
      }
      return PackageEntryPointConflict(
        manifestPath: relativePath(
          packageDirectory.appending(path: "package.json"), repoURL: repoURL),
        declaredPath: relativePath(entryURL, repoURL: repoURL),
        field: entryPoint.field
      )
    }
    return nil
  }

  private static func suspiciousNewFileDetail(
    _ path: String,
    conflict: PackageEntryPointConflict
  ) -> String {
    "- \(path) (\(conflict.manifestPath) \(conflict.field) already points at \(conflict.declaredPath))"
  }

  private static func planExplicitlyMovesEntryPoint(
    to path: String,
    conflict: PackageEntryPointConflict,
    in plan: String
  ) -> Bool {
    let loweredPlan = plan.lowercased()
    let loweredPath = path.lowercased()
    let loweredDeclaredPath = conflict.declaredPath.lowercased()
    let loweredField = conflict.field.lowercased()
    guard loweredPlan.contains(loweredPath),
      loweredPlan.contains(loweredDeclaredPath),
      loweredPlan.contains(loweredField)
    else {
      return false
    }
    return [
      "change",
      "replace",
      "move",
      "point",
      "route",
      "reroute",
    ].contains { loweredPlan.contains($0) }
  }

  private static func isEntryPointAlias(_ path: String) -> Bool {
    let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
    return ["app", "cli", "index", "main", "server"].contains(stem)
  }

  private static func nearestPackageDirectory(from url: URL, repoURL: URL) -> URL? {
    let repoPath = repoURL.standardizedFileURL.path
    var candidate = url.standardizedFileURL
    while candidate.path.hasPrefix(repoPath) {
      let manifestURL = candidate.appending(path: "package.json")
      if FileManager.default.fileExists(atPath: manifestURL.path) {
        return candidate
      }
      let parent = candidate.deletingLastPathComponent().standardizedFileURL
      if parent.path == candidate.path { break }
      candidate = parent
    }
    return nil
  }

  private static func packageEntryPoints(in packageDirectory: URL) -> [(
    field: String, path: String
  )]? {
    let manifestURL = packageDirectory.appending(path: "package.json")
    guard let data = try? Data(contentsOf: manifestURL),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    var entryPoints: [(field: String, path: String)] = []
    for field in ["main", "module", "browser", "types", "typings"] {
      if let raw = object[field] as? String,
        let normalized = normalizedPackageEntryPoint(raw)
      {
        entryPoints.append((field, normalized))
      }
    }
    if let raw = object["bin"] as? String,
      let normalized = normalizedPackageEntryPoint(raw)
    {
      entryPoints.append(("bin", normalized))
    } else if let bin = object["bin"] as? [String: Any] {
      for key in bin.keys.sorted() {
        if let raw = bin[key] as? String,
          let normalized = normalizedPackageEntryPoint(raw)
        {
          entryPoints.append(("bin.\(key)", normalized))
        }
      }
    }
    return entryPoints
  }

  private static func normalizedPackageEntryPoint(_ raw: String) -> String? {
    var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty, !path.hasPrefix("#"), !path.contains("://") else { return nil }
    while path.hasPrefix("./") {
      path.removeFirst(2)
    }
    path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !path.isEmpty, !path.hasPrefix("../") else { return nil }
    return path
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

  private static func claimsNewCLIBehavior(_ text: String) -> Bool {
    guard text.contains("cli") || text.contains("command") else { return false }
    return [
      "print",
      "prints",
      "output",
      "one-line",
      "summary",
      "argument",
      "argv",
      "command",
    ].contains { text.contains($0) }
  }

  private static func isFocusedCoverageVerify(_ normalizedVerify: String) -> Bool {
    normalizedVerify.contains("pnpm test")
      && normalizedVerify.contains("--coverage")
      && !normalizedVerify.contains("typecheck")
      && !normalizedVerify.contains("build")
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
      "packages/",
      ".ts",
      ".tsx",
      "cli behavior",
      "vitest",
      "test file",
      "source file",
    ].contains { text.contains($0) }
  }

  private static func isSimpleDocumentationGrepVerify(_ verify: String) -> Bool {
    let normalized = verify
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern =
      #"^(?:/usr/bin/)?grep\s+-[A-Za-z]*q[A-Za-z]*\s+("[^"]+"|'[^']+'|[^\s;&|]+)\s+[\w./-]+\.(?:md|markdown|txt|rst)$"#
    return normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func claimsCLIImplementationWork(_ text: String) -> Bool {
    [
      "implement",
      "add support",
      "support for",
      "packages/cli/src/main.ts",
      "main.ts",
      "entrypoint",
      "source",
    ].contains { text.contains($0) }
  }

  private static func mentionsTestProof(_ plan: String) -> Bool {
    [
      ".test.",
      " test",
      " tests",
      "vitest",
      "coverage",
      "assert",
      "expect(",
      "packages/cli/src/main.test.ts",
    ].contains { plan.contains($0) }
  }

}
