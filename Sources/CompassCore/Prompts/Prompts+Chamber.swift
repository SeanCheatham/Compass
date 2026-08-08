import Foundation

extension Prompts {
  public static func chamberPrompt(
    recon: ChamberReconResult,
    priorSnapshot: ChamberSnapshot? = nil,
    promptMode: AgentPromptMode = .envelope
  ) throws -> String {
    let reconJSON = try JSONEncoder().encode(recon)
    let reconText = String(decoding: reconJSON, as: UTF8.self)
    let prior =
      priorSnapshot?.formattedForPrompt() ?? "_(no prior chamber snapshot)_"
    let submitExample = """
      {
        "plan": "<what you hunted>",
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
            "description": "<contract violated>",
            "testPath": "tests/compass_gen_example.rs",
            "confidence": 0.7,
            "triage": {
              "isRealBug": true,
              "rationale": "<cite rustdoc / documented contract>"
            },
            "evidence": "<failing assert / output>"
          }
        ],
        "notes": []
      }
      """
    let submitSection =
      promptMode == .nativeTools
      ? """
        Finish by calling the `chamber_submit` tool with these arguments:
        \(submitExample)
        """
      : """
        Finish with exactly this envelope:
        {
          "kind": "chamber_submit",
          "payload": \(submitExample)
        }
        """
    let closing =
      promptMode == .nativeTools
      ? "Use chamber tools, then call `chamber_submit`."
      : "Use `chamber_continue` for tools. Use `chamber_submit` when done."

    return """
      You are the Chamber agent in Compass — an adversarial test hunter for Rust codebases.
      Your job is to write failing tests that surface real bugs. You must not edit production
      sources. Only create or overwrite `tests/compass_gen_*.rs` via `write_generated_test`.

      Ground truth:
      - A product-bug candidate requires a generated test that compiles and fails, or a
        baseline test failure already present.
      - Surviving mutants are coverage gaps, not product bugs (kind `survivingMutant`,
        triage isRealBug=false).
      - Triage must cite a documented contract (rustdoc / crate docs). Invented expectations
        are false positives — set isRealBug=false.
      - Prefer API docs over README inventiveness.

      Tools:
      - read_file, ls, grep, glob, outline, find_symbol, summary, list_files, importers_of
      - write_generated_test (tests/compass_gen_*.rs only)
      - bash (read-only probes + `cargo test`; no production file mutation via shell)

      After writing a test, run `cargo test --test <stem>` (stem = filename without .rs).

      ## Recon
      ```json
      \(reconText)
      ```

      ## Prior chamber snapshot
      \(prior)

      \(submitSection)

      \(closing)
      """
  }
}
