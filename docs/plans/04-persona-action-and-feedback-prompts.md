# 04 - Persona Action And Feedback Prompts

## Objective

Create prompt contracts and JSON schemas for PMF persona action selection and
post-run subjective feedback.

The prompts should produce useful, skeptical product feedback without letting
the persona invent app capabilities or actions.

## Scope

Add prompt builders, schemas, decoding, validation, repair prompts, and tests.
Do not overbuild UI in this plan.

## Action Selection Prompt

The persona action prompt receives:

- product hypothesis summary
- persona
- task
- current semantic app state
- visible copy and semantic nodes
- allowed actions
- prior action transcript
- turn number and max turns

The model must return JSON:

```json
{
  "actionId": "inspect_value_prop",
  "params": {},
  "rationale": "I need to understand whether this solves my reporting pain.",
  "expectation": "I expect to see a concrete workflow or outcome.",
  "confusion": null
}
```

Validation rules:

- `actionId` is required.
- `actionId` must match the allowed action list exactly.
- `rationale` is required and non-empty.
- `params` must be JSON object.
- Unknown top-level fields should be rejected unless existing Compass schema
  decoders intentionally tolerate them.

## Feedback Prompt

After the deterministic trace ends, ask the persona for subjective feedback.

The model receives:

- original product hypothesis
- persona and task
- complete experience trace summary
- transcript of persona action rationales
- terminal app state

The model must return JSON:

```json
{
  "valueScore": 3,
  "clarityScore": 2,
  "trustScore": 3,
  "switchLikelihood": 2,
  "payLikelihood": 1,
  "taskOutcome": "partial",
  "topObjection": "I still cannot tell how this replaces my current spreadsheet.",
  "missingCapability": "A concrete import or reporting example.",
  "momentOfDelight": null,
  "momentOfConfusion": "The first screen says ready but not ready for what.",
  "verdict": "not_yet",
  "summary": "The promise is plausible, but the experience does not prove value quickly."
}
```

Suggested enums:

- `taskOutcome`: `succeeded`, `partial`, `failed`, `abandoned`
- `verdict`: `strong_pull`, `some_pull`, `not_yet`, `wrong_user`

Scores should use a 1 to 5 integer scale. Make labels explicit in the prompt.

## Skepticism Guardrails

The prompt should tell personas:

- Do not be polite.
- Do not assume hidden features.
- Judge only the experience and product claim shown.
- Prefer concrete objections over generic praise.
- Distinguish "I understand it" from "I would use or pay for it."
- Name the current alternative when relevant.

## Prompt Versioning

Add explicit prompt version ids:

- `pmf.persona_action.v1`
- `pmf.feedback.v1`

Persist prompt version ids with each evidence record.

## Repair Flow

If the model returns invalid JSON or schema-invalid output:

- Send one concise repair prompt with the validation error.
- Reuse the same state and allowed actions.
- If repair fails, store a failed evidence record with raw output.

## Likely Files

- `Sources/Compass/Prompts/`
- `Sources/Compass/Resources/Schemas/`
- `Sources/Compass/AgentExecutor/AgentExecutor+Remediation.swift`
- `Sources/Compass/Models.swift`
- `Tests/CompassTests/`

## Acceptance Criteria

- Action prompt produces a strict schema contract.
- Feedback prompt produces a strict schema contract.
- Invalid action ids are rejected.
- Invalid feedback scores are rejected.
- Prompt version ids are included in decoded outputs or run metadata.
- Tests cover valid decode, invalid action, invalid enum, invalid score, and
  repair prompt text.

## Verification

Run:

```bash
./scripts/test-local.sh
```

Add focused tests for prompt builders and schema validation rather than relying
on live model calls.

## Implementation Progress

- Added prompt version ids `pmf.persona_action.v1` and `pmf.feedback.v1`.
- Added PMF persona action prompt and repair prompt builders with skepticism
  guardrails, semantic state context, allowed actions, and strict JSON output
  instructions.
- Added PMF feedback prompt and repair prompt builders with 1-5 score labels,
  `taskOutcome`/`verdict` enums, trace summaries, terminal state, and transcript
  context.
- Added strict resource schemas:
  - `Sources/Compass/Resources/Schemas/pmfPersonaAction.json`
  - `Sources/Compass/Resources/Schemas/pmfFeedback.json`
- Added strict decoders and validation for unknown top-level fields, required
  fields, exact allowed action ids, JSON-object params, non-empty text fields,
  score ranges, and enum values.
- Threaded the persona action prompt version into `PMFPersonaActionChoice` and
  `PMFPersonaActionTranscriptEntry` so later evidence records can persist the
  prompt version.
- Added focused tests for valid decode, invalid action id, non-object params,
  unknown fields, invalid feedback score, invalid enum, prompt text, repair
  prompt text, and schema loading.

## Completion

Status: complete.

Completed on 2026-06-04 after adding PMF persona action and feedback prompt
contracts, strict schemas, strict decoders, repair prompts, prompt-version
threading, and focused contract tests.

Verification passed:

- `./scripts/test-local.sh --filter PMFPromptContractTests`
- `./scripts/test-local.sh --filter PMFSimulationRunnerTests`
- `./scripts/test-local.sh --filter PromptSchemaLoadingTests`
- `./scripts/test-local.sh` (1822 tests)
