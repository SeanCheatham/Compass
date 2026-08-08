import Foundation

extension Prompts {
  public static func healthPrompt(
    recon: HealthReconResult,
    priorSnapshot: HealthSnapshot? = nil,
    focus: HealthFocus,
    promptMode: AgentPromptMode = .envelope
  ) throws -> String {
    let reconJSON = try JSONEncoder().encode(recon)
    let reconText = String(decoding: reconJSON, as: UTF8.self)
    let prior =
      priorSnapshot?.formattedForPrompt() ?? "_(no prior health snapshot)_"
    let focusGuidance = focusDetail(focus)
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
      - Surviving mutants are coverage gaps (`survivingMutant`, isRealBug=false).
      - Docs/sprawl findings use kinds `staleDoc`, `orphanedSurface`, `testGap`, `deadCode`.
      - Triage for bugs must cite a documented contract. Invented expectations are false positives.
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

  private static func focusDetail(_ focus: HealthFocus) -> String {
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
      return """
        Focus rules — cleanup / sprawl:
        - Remove dead code, consolidate duplication, delete orphaned surfaces when evidence is clear.
        - Leave behavior unchanged; run verify (`cargo test` / fmt / clippy) before submit.
        - Prefer surgical slices over speculative refactors.
        """
    }
  }
}
