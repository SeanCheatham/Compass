import Foundation

extension Prompts {
  public static func requirementsAuditPrompt(
    brief: ProjectBrief,
    ledger: RequirementLedger,
    requirementIDs: [String]?,
    criterionResults: [RequirementCriterionResult] = [],
    codemapHint: String = "",
    commit: String? = nil,
    promptMode: AgentPromptMode = .envelope
  ) -> String {
    let reconciled = ledger.reconciled(with: brief)
    let scopedIDs: [String]
    if let requirementIDs, !requirementIDs.isEmpty {
      scopedIDs = requirementIDs
    } else {
      scopedIDs = brief.nonEmptyRequirements.map(\.id)
    }
    let scopedRequirements = brief.nonEmptyRequirements.filter { scopedIDs.contains($0.id) }

    var scopeLines: [String] = []
    for requirement in scopedRequirements {
      let entry = reconciled.entry(for: requirement.id)
      scopeLines.append("- id: `\(requirement.id)`")
      scopeLines.append("  text: \(requirement.text)")
      scopeLines.append(
        "  kind/proof: \(requirement.kind.rawValue)/\(requirement.proofLevel.rawValue)")
      if let owned = entry?.ownedPaths, !owned.isEmpty {
        scopeLines.append("  owned paths: \(owned.map { "`\($0)`" }.joined(separator: ", "))")
      }
      if let scenarios = entry?.scenarios, !scenarios.isEmpty {
        scopeLines.append("  scenarios:")
        for scenario in scenarios {
          scopeLines.append("  ```")
          scopeLines.append(scenario.renderedMarkdown)
          scopeLines.append("  ```")
        }
      }
      let commands = entry?.executableCommands ?? []
      if commands.isEmpty {
        scopeLines.append("  criteria: _(none)_")
      } else {
        scopeLines.append("  criteria:")
        for criterion in commands {
          scopeLines.append("  - `\(criterion)`")
        }
      }
      if let status = entry?.status {
        scopeLines.append("  prior status: \(status.rawValue)")
      }
      if let latest = entry?.shipTraces.last {
        var bits: [String] = []
        if let session = latest.session { bits.append("session \(session)") }
        if let commit = latest.commit { bits.append("commit \(commit.prefix(8))") }
        scopeLines.append("  latest ship: \(bits.joined(separator: ", "))")
      }
    }

    var criterionLines: [String] = []
    for result in criterionResults where scopedIDs.contains(result.requirementID) {
      let status = result.passed ? "passed" : "FAILED (exit \(result.exitCode))"
      criterionLines.append(
        "- [\(status)] id=`\(result.requirementID)` cmd=`\(result.command)` — \(compactCriterionOutput(result.output))"
      )
    }

    let submitExample = """
      {
        "results": [
          {
            "requirementID": "<id>",
            "verdict": "satisfied",
            "evidence": ["<file path or command evidence>"],
            "proposedCriteria": ["<optional shell command>"],
            "proposedOwnedPaths": ["crates/cli/src"],
            "proposedScenarios": [
              {
                "given": "a built CLI",
                "whenAction": "user runs `cargo run -p cli -- --help`",
                "thenExpectations": ["exit 0", "help text mentions the feature"],
                "command": "cargo run -p cli -- --help"
              }
            ]
          }
        ],
        "summary": "<overall requirements status>"
      }
      """
    let submitSection =
      promptMode == .nativeTools
      ? """
        Finish by calling the `requirements_audit_submit` tool with these arguments:
        \(submitExample)

        """
      : """
        Finish with exactly this envelope:
        {
          "kind": "requirements_audit_submit",
          "payload": \(submitExample)
        }

        """
    let closingLine =
      promptMode == .nativeTools
      ? "Use read-only tools and bash probes as needed, then call `requirements_audit_submit`."
      : "Use `requirements_audit_continue` for any read-only tool or bash probe. Use `requirements_audit_submit` when decided."

    return """
      You are the Requirements Audit agent in Compass, a local software factory. Decide whether
      each in-scope product requirement is currently satisfied by the repository/product.

      Do not edit files or commit. Use read-only tools and bash probes. Prefer concrete evidence.

      Audit rules:
      - Return one result for every in-scope requirement id listed below.
      - Verdict is `satisfied` or `unsatisfied` only.
      - Respect proof level:
        - `deterministic`: host-run criteria/scenario commands decide; propose commands if missing.
        - `hybrid`: commands plus judgment with citations; FAILED criteria force unsatisfied.
        - `judgment`: citations required; commands optional.
      - Prefer Given/When/Then scenarios in `proposedScenarios` over opaque bash when describing
        product behavior. Put the executable probe in `command` when one exists.
      - Propose `proposedOwnedPaths` (repo-relative prefixes) so future ships can mark this
        requirement stale when those paths change.
      - Cite evidence (paths, commands, observable behavior). Do not invent requirements.
      - Host-run criterion results below are authoritative for deterministic/hybrid proof.
      - Product requirements are user-owned. Judge the product against them; do not rewrite them.

      \(submitSection)## Project brief
      \(brief.renderedMarkdown())

      ## Requirements under audit
      \(scopeLines.isEmpty ? "_(none)_" : scopeLines.joined(separator: "\n"))

      ## Host-run criterion results
      \(criterionLines.isEmpty ? "_(no host-run criteria)_" : criterionLines.joined(separator: "\n"))

      ## Requirements ledger status
      \(reconciled.renderedStatusMarkdown(brief: brief))

      ## Codemap hint
      \(codemapHint.isEmpty ? "_(none)_" : codemapHint)

      ## Commit under review
      \(commit?.isEmpty == false ? commit! : "_(none)_")

      \(closingLine)
      """
  }

  private static func compactCriterionOutput(_ output: String, limit: Int = 200) -> String {
    let compact =
      output
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard compact.count > limit else { return compact.isEmpty ? "(no output)" : compact }
    return String(compact.prefix(limit - 3)) + "..."
  }
}
