# Compass Pain-Driven Productization Plans

This directory is the implementation runway for turning Compass from a
product-idea factory into a pain-driven productization loop.

The superseded app-fit simulation direction asked: "Does this generated app
look useful?" The productization direction asks: "Given this user pain, which
product bet relieves it well enough to deserve promotion?"

Breaking changes are allowed. Prefer clean model changes over compatibility
layers when compatibility would preserve the wrong product shape.

## Target Loop

```text
raw user pain
-> Discover models the pain, users, current workflow, and alternatives
-> Compass proposes multiple solution hypotheses
-> each active solution gets an experiment branch and worktree
-> Develop builds a Rust desktop prototype for one experiment
-> deterministic simulations and persona runs collect evidence
-> Reflect decides continue, narrow, pivot, kill, or promote
-> promoted experiments merge into the main product direction
```

## Plan Order

1. `00-goal-and-architecture.md`
2. `01-product-hypothesis-model.md`
3. `02-generated-experience-contract.md`
4. `03-experiment-branches-and-worktrees.md`
5. `04-persona-action-and-feedback-prompts.md`
6. `05-evidence-store-and-ui.md`
7. `06-plan-reflect-feedback-loop.md`
8. `07-verification-and-rollout.md`
9. `08-git-backed-promotion-and-archive.md`
10. `09-scenario-authoring-and-run-controls.md`

The filenames retain the prior plan numbering, but the contents now describe
the pain-driven productization epic.

## Done Definition

The epic is complete when Compass can:

- Accept a rough user pain as the project seed.
- Store a structured pain model, current workflow, user segments, alternatives,
  solution hypotheses, product experiments, and product decisions.
- Create isolated experiment branches and worktrees for competing solution
  bets.
- Build generated Rust desktop prototypes whose deterministic experience
  contract references the pain, solution, experiment, and current alternative.
- Run deterministic and model-backed simulations against specific experiment
  commits.
- Store evidence by experiment, branch, commit, scenario, persona, prompt
  version, model, trace hash, and decision.
- Feed pain-relief evidence into Plan and Reflect without treating subjective
  evidence as a Verify gate.
- Promote, archive, or kill experiment branches with an auditable decision
  trail.

## Implementation Rules

- Treat pain as durable and solution hypotheses as disposable.
- Keep generated project code Rust-only and preserve the blessed Cargo workspace
  shape.
- Keep app behavior replayable through pure `app-core` transitions and explicit
  JSON CLI contracts.
- Allow only one mutating agent run per experiment branch at a time.
- Allow read-only simulations to run in parallel against verified commits.
- Use screenshots and visual verification as rendering proof, not the main
  productization oracle.
- Store subjective model output with provenance. Never pretend it is a
  deterministic test result.
- Make promotion a deliberate product decision, not an automatic side effect of
  passing build checks.
