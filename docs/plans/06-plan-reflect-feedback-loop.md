# 06 - Plan Reflect Feedback Loop

## Objective

Feed PMF evidence back into Compass's planning loop as product pressure. Plan
and Reflect should see recurring simulated-user findings and use them to choose
better next increments.

## Scope

Add PMF evidence summaries to Plan/Reflect context and prompts. Do not make PMF
feedback a hard gate for Verify.

## Planning Semantics

PMF evidence is advisory:

- It can motivate product changes.
- It can reprioritize roadmap items.
- It can challenge the product hypothesis.
- It can suggest new PMF scenarios.
- It should not automatically fail Develop post-checks.

Plan should distinguish:

- Engineering failures: build/test/verify problems.
- Product risks: simulated personas did not understand or desire the product.
- Evidence gaps: PMF scenarios are missing, stale, or too shallow.

## Context Injection

Before Plan and Reflect, gather a bounded PMF summary:

- current hypothesis
- latest evidence per active scenario
- repeated objections
- low-score clusters
- recent verdict distribution
- suggested next PMF scenario gaps

Keep the context compact. Prefer structured bullet summaries over raw
transcripts. Raw evidence should be available through tools or file references
if needed.

## Prompt Updates

Update Plan prompt guidance:

- Consider PMF evidence when choosing immediate work.
- Prefer changes that directly address repeated target-persona confusion or
  objections.
- If evidence is thin, plan an increment that improves the experience contract
  or adds a better scenario.
- Do not blindly optimize for simulated praise.
- Preserve engineering verification discipline.

Update Reflect prompt guidance:

- Extract durable product lessons from repeated PMF evidence.
- Distinguish a persona-specific objection from a cross-cohort risk.
- Suggest hypothesis edits only when evidence supports them.

## Optional Develop Guidance

Develop can receive the active PMF objective when implementing a PMF-driven
increment. It should not receive giant transcripts unless necessary.

## PMF Run Trigger

Add one conservative automatic trigger:

- After a successful Rust generated-project Verify, run PMF scenarios only when
  PMF simulation is enabled for the project and the app exposes the experience
  contract.

If automatic execution is risky or slow, start with a manual "Run PMF
Simulation" command and let Plan recommend using it.

## Likely Files

- `Sources/Compass/Prompts/Prompts+Plan.swift`
- `Sources/Compass/Prompts/Prompts+Reflect.swift`
- `Sources/Compass/Prompts/Prompts+Develop.swift`
- `Sources/Compass/CompassProject+RunPasses.swift`
- `Sources/Compass/PlanReliabilityFeedback.swift`
- `Sources/Compass/ProjectLessonsGuide.swift`
- `Tests/CompassTests/`

## Acceptance Criteria

- Plan context includes bounded PMF evidence when available.
- Reflect can update product lessons from PMF evidence.
- Prompts clearly mark PMF findings as advisory product evidence.
- PMF evidence can motivate immediate work without bypassing normal Verify.
- Tests cover prompt/context generation with no evidence, successful evidence,
  failed PMF runs, and repeated objections.

## Verification

Run:

```bash
./scripts/test-local.sh
```

Manually inspect one generated Plan prompt fixture or debug output to confirm
PMF evidence is concise and not raw-transcript-heavy.

## Implementation Progress

- Added `PMFPlanningEvidenceFormatter` to build compact advisory PMF context
  from `PMFConfig` and `PMFEvidenceIndex`.
- The PMF context includes the current hypothesis, latest evidence per enabled
  scenario, repeated objections, low-score persona/task clusters, verdict
  distribution, run failures, and evidence gaps.
- Updated Plan prompt guidance to treat PMF findings as advisory product
  pressure that can motivate work without bypassing normal Verify.
- Updated Reflect prompt guidance to extract durable product lessons only from
  repeated or clearly consequential PMF evidence.
- Wired Plan and Reflect launch paths to pass workspace PMF config and evidence
  index into prompt generation.
- Added focused prompt/context tests for empty evidence, successful evidence,
  failed PMF runs, repeated objections, low-score clusters, and Plan/Reflect
  PMF context injection.

## Completion

Status: complete on 2026-06-04.

Verification:

- `./scripts/test-local.sh --filter PMFPlanningEvidenceFormatterTests` passed
  with 5 tests.
- `./scripts/test-local.sh --filter PlanPromptTests` passed with 27 tests.
- `./scripts/test-local.sh` passed with 1831 tests in 185 suites.
- Manually inspected the generated Plan prompt debug output from the focused
  PMF prompt test; the PMF section is structured, concise, and does not include
  raw transcripts.

Rollout boundary: this plan injects PMF evidence into Plan/Reflect as advisory
product context. Disabled-by-default execution controls, end-to-end smoke, and
manual run documentation are covered by Plan 07.
