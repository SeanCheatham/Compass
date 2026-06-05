# 08 - Git-Backed Promotion And Archive

## Objective

Turn productization rollout decisions into explicit git operations after the UI
has recorded an evidence-backed promote or archive decision.

Plan 07 added the Productization workbench and decision workflow. This follow-up
keeps the next increment focused on branch mechanics: verify the experiment
branch, present the branch delta, promote by merge or fast-forward, and archive
without deleting lineage.

## Scope

Implement git-backed promote/archive actions for product experiments.

This plan should not reintroduce legacy PMF state, prompt schemas, evidence
stores, or generated command aliases.

## Promotion Flow

Promotion should:

- confirm the experiment is currently `promote`
- verify the experiment branch and current sha still match productization state
- show a bounded branch diff/risk summary before the final action
- fast-forward or merge the experiment branch into the accepted product branch
- record before/after commit ids on a `promoted` `ProductDecision`
- update the solution status to `promoted`
- leave the experiment branch available for audit

Start with fast-forward where possible and normal merge when necessary. Do not
add squash promotion unless Explore and session history can still explain the
lineage.

## Archive Flow

Archiving should:

- confirm the experiment is currently `kill`
- preserve the worktree and evidence records
- optionally create or update `compass/archive/<solution-slug>`
- mark the experiment as `archived`
- mark the solution as `parked`
- record the branch name and commit ids on the decision trail

Do not delete branches or worktrees automatically.

## Acceptance Criteria

- Promotion refuses stale branch state unless the user refreshes or explicitly
  resolves the mismatch.
- Promotion records the accepted product branch commit before and after the git
  operation.
- Archive preserves branch, worktree, and evidence lineage.
- The workbench can show enough branch delta context for a user to confirm the
  operation deliberately.
- Focused tests cover fast-forward promotion, merge-required promotion, stale
  sha rejection, and archive ref creation.

## Verification

- Run focused Swift tests for rollout git operations.
- Use temporary git repositories to prove branch and worktree lineage.
- Run productization rollout prompt/context tests to confirm no raw transcripts
  enter Plan or Reflect.
- Run scaffold tests to confirm generated projects still expose only
  productization command names.

## Status

Planned.
