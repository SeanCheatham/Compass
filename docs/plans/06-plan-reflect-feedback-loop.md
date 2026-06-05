# 06 - Plan Reflect Productization Loop

## Objective

Teach Plan and Reflect to use productization state and evidence when choosing
work.

The planning loop should no longer optimize only for implementing the current
app. It should decide whether to continue, narrow, pivot, kill, or promote
experiments based on pain-relief evidence.

## Scope

Update prompt context, state transitions, plan validation, reflect behavior, and
session records.

This plan does not add the full UI or merge/promotion workflow. It makes the
agent loop productization-aware.

## Plan Semantics

Plan may choose immediate work from:

- raw pain or unresolved pain unknowns
- active solution hypotheses
- an experiment branch needing implementation
- evidence gaps
- repeated objections
- missing capabilities
- promotion preparation
- kill/archive cleanup
- normal repository repair

Plan should pick one commit-sized slice. It should not attempt to implement
several experiments in one immediate handoff.

## Reflect Semantics

Reflect should evaluate:

- Did the latest implementation improve an active experiment?
- Did evidence reduce or increase confidence in the solution?
- Should the experiment continue, narrow, pivot, kill, or promote?
- Are new solution hypotheses warranted?
- Are scenarios too weak to test the pain?
- Are repeated objections product issues or scenario/model artifacts?

Reflect may update productization state but must not mutate code.

## Prompt Guidance

Plan prompt rules should say:

- Start with the pain and active experiment context.
- Prefer implementation work that can create or clarify evidence.
- Treat subjective evidence as product pressure, not a Verify gate.
- Preserve branch isolation.
- Use deterministic simulation fixtures before live persona runs when possible.
- If evidence is weak because the prototype is too shallow, plan a better
  product slice rather than declaring the pain invalid.

Reflect prompt rules should say:

- Be skeptical of one-off persona feedback.
- Pay attention to repeated objections across scenarios.
- Separate pain validity from solution validity.
- Recommend killing solutions that repeatedly fail to beat current alternatives.
- Recommend promotion only when evidence and Verify both support it.

## State Transitions

Allowed experiment decision transitions:

```text
not_run -> continue
continue -> continue | narrow | pivot | kill | promote
narrow -> continue | pivot | kill | promote
pivot -> continue | kill
kill -> archived
promote -> promoted
```

The host should validate transitions and require a decision summary for `kill`
and `promote`.

## Session Records

Session history should include:

- experiment id
- solution id
- pain id
- branch name
- before sha
- after sha
- evidence run ids
- product decision, if any

This lets Explore explain not only what changed, but which product bet the
change served.

## Likely Files

- `Sources/Compass/Prompts/Prompts+Plan.swift`
- `Sources/Compass/Prompts/Prompts+Reflect.swift`
- `Sources/Compass/CompassProject+RunPasses.swift`
- `Sources/Compass/PlanProposal.swift`
- `Sources/Compass/PlanTransitionValidator.swift`
- `Sources/Compass/SessionRecordStore.swift`
- `Sources/Compass/ReflectSessionBrief.swift`
- productization state and evidence helpers

## Acceptance Criteria

- Plan prompt includes bounded productization state and latest evidence.
- Reflect can update experiment decisions.
- Plan validation prevents multi-experiment immediate work unless explicitly
  scoped to shared infrastructure.
- Session records preserve experiment and branch identity.
- Productization evidence can motivate work without bypassing normal Verify.

## Verification

- Run prompt tests for Plan and Reflect.
- Add transition validator tests for experiment decisions.
- Add session record encoding tests for experiment metadata.
- Manually inspect a Plan prompt with active experiments and evidence.

## Status

Complete on 2026-06-04.

Implementation notes:

- Added productization-aware Plan validation for multi-experiment immediate
  handoffs, with an explicit shared-infrastructure escape hatch.
- Added Reflect product decision updates, allowed transition validation, and
  persisted decision trail updates.
- Extended session records with pain, solution, branch, before/after sha,
  evidence run ids, and product decision metadata.
- Tightened Plan and Reflect prompt guidance around evidence, branch isolation,
  deterministic simulation, and experiment decisions.

Verification:

- `./scripts/test-local.sh --filter ProductizationLoopTests` passed with 4
  tests.
- `./scripts/test-local.sh --filter PlanTransitionValidatorTests` passed with
  16 tests.
- `./scripts/test-local.sh --filter ProductizationEvidenceStoreTests` passed
  with 3 tests.
- `./scripts/test-local.sh --filter PromptSchemaLoadingTests` passed with 7
  tests.
- `./scripts/test-local.sh --filter PlanDomainTests` passed with 63 tests.
- `./scripts/test-local.sh --filter ProductExperimentWorktreeTests` passed with
  6 tests.
- `./scripts/test-local.sh --filter AgentExecutorTests` passed with 74 tests.
- `./scripts/test-local.sh --filter ProductizationConfigTests` passed with 8
  tests.
- `./scripts/test-local.sh --filter DiscoverPromptContractTests` passed with 7
  tests.
- `./scripts/test-local.sh --filter ProductizationEvidenceStoreTests` passed
  with 3 tests.
