# 02 - Discovery Phase And Prompt Contracts

## Objective

Add a discovery phase that turns raw user pain into structured productization
state before Compass starts implementation.

Discovery should generate pain hypotheses, user segments, current workflows,
alternatives, solution hypotheses, and experiment candidates. Plan can then pick
the next commit-sized slice from real product context instead of guessing from a
single product idea.

## Scope

Implement the prompt contracts and validation for a new Discover pass or a
clearly separated Plan pre-pass.

This plan should not yet create branches or generate prototypes. It prepares the
state that later plans will use.

## Inputs

Discovery receives:

- raw user pain
- existing `COMPASS.md`
- drafts
- lessons
- assumptions
- current productization state
- latest evidence summary
- repository shape, if a repo already exists

## Submit Result Shape

Discovery returns:

```text
summary
stateEdits
candidateExperiments
openQuestions
lessonEdits
assumptions
```

`stateEdits` should be structured, not free-form Markdown. The host applies
them to `ProductizationConfig` after validation.

## Discovery Rules

Prompt guidance should require:

- Start from pain, not a solution.
- Name the user segment before naming the app.
- Describe what users do today.
- Include non-software alternatives.
- Generate multiple solution hypotheses when the pain is broad.
- Make each experiment small enough to become a Rust desktop prototype.
- Record unknowns that would materially change the product direction.
- Avoid inventing evidence. Use "assumption" for guesses.

## Candidate Experiment Rules

Each candidate experiment should include:

- solution hypothesis id
- prototype name
- branch slug
- smallest workflow to prove
- target scenario cohort
- expected evidence signal
- kill criteria

Example:

```text
Pain: small SaaS teams lose incident decisions in Slack.
Solution: Runbook Desk.
Prototype: triage board with timeline, owner queue, and status composer.
Evidence signal: persona can produce a clearer customer update than current workflow.
Kill criteria: persona still prefers Slack thread plus checklist.
```

## Validation

Host-side validation should reject discovery output when:

- no pain hypothesis is active
- solution hypotheses do not reference a pain
- experiments do not reference a solution
- branch slugs are invalid git ref components
- open questions are used instead of actionable next steps
- state updates exceed prompt or storage bounds

## UI Entry

The project intake UI should shift from "describe the product" to "describe the
pain."

Suggested prompt:

```text
What user pain should Compass explore?
```

Supporting text should ask for context, current workflow, and who feels the pain
without requiring a technical spec.

## Likely Files

- `Sources/Compass/Prompts/Prompts+System.swift`
- `Sources/Compass/Prompts/Prompts+Plan.swift`
- new `Sources/Compass/Prompts/Prompts+Discover.swift`
- `Sources/Compass/CompassProject+RunPasses.swift`
- `Sources/Compass/AgentExecutor/`
- `Sources/Compass/ProjectIntakeGuide.swift`
- `Sources/Compass/Views/`
- `Sources/Compass/Resources/Schemas/`

## Acceptance Criteria

- A raw pain can produce valid productization state without implementation work.
- Discovery output is validated before storage mutation.
- Product candidates are framed as experiments, not guaranteed product specs.
- Branch slugs and experiment ids are available for later plans.
- The UI language asks for pain and current workflow rather than a product idea.

## Verification

- Run prompt schema tests for Discover.
- Add tests that invalid discovery output triggers remediation.
- Manually inspect one generated Discover prompt.
- Confirm the project can proceed from empty repo state to productization state.

## Status

Complete.

Completed on 2026-06-04. Added a Discover prompt contract in
`Sources/Compass/Prompts/Prompts+Discover.swift` with prompt version
`discover.productization.v1`, structured `stateEdits`, candidate experiments,
open questions, lesson edits, and assumptions. The prompt starts from raw user
pain, current workflow, alternatives, user segments, and small Rust desktop
experiment candidates rather than treating the first product idea as the target.

Added strict schema loading for `Sources/Compass/Resources/Schemas/discover.json`
and host-side response decoding/validation. Validation rejects missing active
pain, broken pain/solution/experiment references, invalid git branch slugs,
open questions used in place of actionable next steps, and oversized state
updates. `CompassWorkspace.applyDiscoverOutput` validates before writing
`.compass/productization.json`.

Updated project intake language to ask what user pain Compass should explore,
including who feels it, what they do today, current alternatives, success
signals, and guardrails.

Verification completed and passed:

```bash
./scripts/test-local.sh --filter DiscoverPromptContractTests
./scripts/test-local.sh --filter PromptSchemaLoadingTests
./scripts/test-local.sh --filter ProjectIntakeGuideTests
```
