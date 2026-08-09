import Foundation

extension Prompts {
  public static func healthPrompt(
    recon: HealthReconResult,
    priorSnapshot: HealthSnapshot? = nil,
    focus: HealthFocus,
    deletionProbe: DeletionProbeResult? = nil,
    promptMode: AgentPromptMode = .envelope
  ) throws -> String {
    let reconJSON = try JSONEncoder().encode(recon)
    let reconText = String(decoding: reconJSON, as: UTF8.self)
    let prior =
      priorSnapshot?.formattedForPrompt() ?? "_(no prior health snapshot)_"
    let focusGuidance = focusDetail(focus, recon: recon, deletionProbe: deletionProbe)
    let submitExample = """
      {
        "plan": "<what you did>",
        "focus": "\(focus.rawValue)",
        "generatedTests": [
          {
            "path": "tests/compass_gen_example.rs",
            "targetHint": "<api>",
            "compiled": true,
            "passed": false,
            "compileErrors": null
          }
        ],
        "findings": [
          {
            "kind": "failingGeneratedTest",
            "title": "<short title>",
            "description": "<contract violated or debt>",
            "testPath": "tests/compass_gen_example.rs",
            "confidence": 0.7,
            "triage": {
              "isRealBug": true,
              "rationale": "<cite rustdoc / documented contract>"
            },
            "evidence": "<failing assert / output / citation>"
          }
        ],
        "notes": []
      }
      """
    let submitSection =
      promptMode == .nativeTools
      ? """
        Finish by calling the `health_submit` tool with these arguments:
        \(submitExample)
        """
      : """
        Finish with exactly this envelope:
        {
          "kind": "health_submit",
          "payload": \(submitExample)
        }
        """
    let closing =
      promptMode == .nativeTools
      ? "Use health tools, then call `health_submit`."
      : "Use `health_continue` for tools. Use `health_submit` when done."

    return """
      You are the Health agent in Compass — improve an imported Rust repo along one focus.
      Current focus: **\(focus.displayName)** (`\(focus.rawValue)`).

      \(focusGuidance)

      Ground truth:
      - Product-bug candidates need a generated test that compiles and fails, or a baseline failure.
      - Docs/sprawl findings use kinds `staleDoc`, `orphanedSurface`, `testGap`, `deadCode`.
      - Triage for bugs must cite a documented contract. Invented expectations are false positives.
      - Use `file_history` / `annotate` (host version history) for provenance; guest bash has no project `.git`
        (CLT may provide `/usr/bin/git`, but the synced tree is gitless).
      - Baseline failures that only reflect sandbox layout (no project `.git`, or fixtures tied to another
        absolute worktree root) are environment noise (`isRealBug=false`) — do not patch product code for them.
      - Proposed patches stay on the Compass health branch; do not merge upstream yourself.

      ## Recon
      ```json
      \(reconText)
      ```

      ## Prior health snapshot
      \(prior)

      \(submitSection)

      \(closing)
      """
  }

  private static func focusDetail(
    _ focus: HealthFocus,
    recon: HealthReconResult,
    deletionProbe: DeletionProbeResult?
  ) -> String {
    switch focus {
    case .bugHunt:
      return """
        Focus rules — bug hunt:
        - Only create/overwrite `tests/compass_gen_*.rs` via `write_generated_test`.
        - Do not edit production sources.
        - After writing a test, run `cargo test --test <stem>`.
        """
    case .test:
      return """
        Focus rules — tests:
        - Improve the suite under `tests/**` only (scoped write_file / edit_file).
        - Prefer real behavior coverage over brittle implementation pins.
        - Run the affected tests via bash.
        """
    case .docs:
      return """
        Focus rules — docs:
        - Edit README*, docs/**, and Markdown files only.
        - Fix stale or wrong docs first; prefer contributor-facing context.
        - Verify with a cheap check (grep/content or build) when possible.
        """
    case .cleanup:
      return cleanupFocusDetail(recon: recon, deletionProbe: deletionProbe)
    }
  }

  private static func cleanupFocusDetail(
    recon: HealthReconResult,
    deletionProbe: DeletionProbeResult?
  ) -> String {
    var sections: [String] = [
      """
      Focus rules — cleanup / sprawl:
      - Remove dead code, consolidate duplication, delete orphaned surfaces when evidence is clear.
      - Leave behavior unchanged; run verify (`cargo test` / fmt / clippy) before submit.
      - Prefer surgical slices over speculative refactors.
      - Uncovered / cold paths are prioritization leads, not proof of dead code.
      - For proven deletion-tested cuts below: apply them and report `deadCode` findings with
        high confidence and evidence stamped `deletion-tested`.
      - For tangled candidates: use compile-error context; expand or abandon surgically.
      """
    ]

    let cold = HealthRecon.coldSourceFiles(from: recon.coverage ?? CoverageSnapshot()).prefix(12)
    if !cold.isEmpty {
      sections.append("Cold files — inspect first (coverage lead, not proof):")
      for entry in cold {
        let pct = entry.lineCoveragePercent.map { String(format: "%.1f%%", $0) } ?? "?"
        sections.append("- `\(entry.path)`: \(pct)")
      }
    }

    if let probe = deletionProbe, !probe.items.isEmpty {
      sections.append(probe.formattedForPrompt())
    } else if !recon.deadCodeCandidates.isEmpty {
      sections.append("Rustc dead-code candidates (not yet deletion-tested):")
      for candidate in recon.deadCodeCandidates.prefix(20) {
        sections.append("- \(candidate.shortLabel): \(candidate.message)")
      }
    }

    return sections.joined(separator: "\n")
  }
}
