# 00 - Goal And Architecture

## Objective

Add a Compass-only PMF simulation capability that runs LLM personas through
semantic product journeys in generated Rust apps and turns the results into
actionable product evidence.

This plan establishes boundaries and sequencing. Implement it as documentation
and lightweight scaffolding first, then use later plans for concrete model,
runner, prompt, UI, and Plan integration work.

## Product Bet

Compass can attack "building the wrong product" by repeatedly asking simulated
target users to try the current app, describe their expectations, and explain
whether the experience feels valuable.

This is not QA automation. The output is advisory product evidence:

- Where personas got confused.
- Which value promises felt credible.
- Which workflows produced desire or skepticism.
- Which objections repeated across a cohort.
- Whether a product variant appears to improve a target journey.

## Compass-Only Determinism Model

The first version approximates determinism by tightly controlling generated app
shape:

- Load-bearing behavior lives in Rust `app-core`.
- App state is serializable.
- User actions are serializable.
- The app exposes allowed actions for each semantic state.
- The experience trace is stable JSON.
- Screenshots are optional supporting proof, not the main PMF assertion surface.

LLM persona judgment is not deterministic. Treat it as sampled opinion with
strong provenance:

- model id
- prompt version
- persona id
- scenario id
- app commit
- trace hash
- timestamp
- raw transcript
- structured feedback

## New Concepts

- Product hypothesis: target user, job, pain, promise, alternatives, success
  criteria, pricing or switching assumptions.
- Persona: a simulated user or buyer with goals, context, constraints,
  skepticism, and decision criteria.
- PMF task: a product journey or buying situation the persona attempts.
- Experience state: the semantic state of the generated app.
- Experience action: one allowed user action selected by the persona agent.
- Experience trace: ordered states, actions, rationales, and app observations.
- PMF feedback: subjective post-run assessment of value, clarity, trust,
  switching likelihood, payment likelihood, objections, and desired changes.
- PMF evidence: the stored unit Compass can show and feed back into planning.

## Non-Goals

- Do not run full desktop automation as the first PMF loop.
- Do not require Murphy, VMM snapshots, Linux images, or nested virtualization.
- Do not use persona feedback as a hard verify failure.
- Do not let LLM personas invent actions outside the generated app's allowed
  action list.
- Do not build a generic survey product. This stays inside Compass's factory
  loop.

## Expected Repository Shape

Likely Compass files:

- `Sources/Compass/Models.swift`
- `Sources/Compass/CompassProject+Storage.swift`
- `Sources/Compass/RustProjectScaffold.swift`
- `Sources/Compass/Prompts/`
- `Sources/Compass/AgentExecutor/`
- `Sources/Compass/Views/`
- `Sources/Compass/Resources/Schemas/`
- `crates/compass-engine/src/scaffold.rs`
- `crates/compass-engine/tests/scaffold_check.rs`

Likely generated Rust project additions:

- `schemas/product-hypothesis.schema.json`
- `schemas/pmf-scenario.schema.json`
- `schemas/experience-input.schema.json`
- `schemas/experience-trace.schema.json`
- `crates/app-core` experience models and pure transitions
- `crates/app-cli experience --input '<json>'`
- `xtask pmf-smoke`

## Acceptance Criteria

- This plan set is present and ordered.
- Later plans can be implemented independently in sequence.
- The PMF feature has a clear Compass-only boundary.
- The shared vocabulary appears consistently in docs and future code.

## Verification

- Read every file in `docs/plans/`.
- Confirm no plan requires Murphy for the first implementation.
- Confirm each later plan has explicit acceptance criteria and test guidance.

## Completion

Status: Complete.

Completed on 2026-06-04. The plan set is present, ordered, and scoped to a
Compass-only semantic PMF loop. Later plans have explicit acceptance criteria and
verification guidance, and none require Murphy for the first implementation.
