# Product Tournament Current Invariants

## Required References

- `ProductTournament.painID` must reference an existing `PainHypothesis`.
- `ProductTournament.contenderIDs` must reference `ProductTournamentContender` records in the same tournament.
- `ProductTournament.roundIDs` must reference `ProductTournamentRound` records in the same tournament.
- `ProductTournament.currentRoundID`, when present, must reference one of that tournament's rounds.
- `ProductTournamentContender.tournamentID` must reference an existing tournament.
- `ProductTournamentContender.contenderPlanID` must reference an existing `ProductTournamentContenderPlan`.
- `ProductTournamentContender.experimentID`, when present, must reference an existing `ProductTournamentExperiment`.
- `ProductTournamentRound.tournamentID` must reference an existing tournament.
- `ProductTournamentRound.contenderIDs` must reference contenders that belong to the same tournament.
- `ProductTournamentRound.scenarioCohortIDs` must reference existing `ProductScenarioCohort` records.
- `ProductScenarioCohort.experimentID` must reference an existing experiment.
- `ProductScenarioCohort.scenarioIDs` must reference scenarios for the same experiment.
- `ProductScenario.experimentID`, `segmentID`, and `currentWorkflowID` must reference existing records.
- `ProductScenario.alternativeID`, when present, must reference an existing alternative.

## Status Fields

- `PainHypothesis.status` tracks whether the pain is draft, active, reframed, resolved, or parked.
- `ProductTournament.status` tracks draft/active/completed/archive lifecycle.
- `ProductTournament.currentRoundID` points at the current tournament round.
- `ProductTournamentRound.status` tracks planned/active/completed/skipped round lifecycle.
- `ProductTournamentContender.status` tracks competing/narrowed/revision/eliminated/winner/archive lifecycle.
- `ProductTournamentContenderPlan.status` tracks candidate/active/promoted/rejected/parked plan lifecycle.
- `ProductTournamentExperiment.decision` tracks implementation decision state.
- `ProductTournamentDecision` stores append-style decision history.

## Known Drift Risks

- Tournament `currentRoundID` can disagree with the active round's `status`.
- A contender can remain listed in future rounds after being eliminated.
- A contender plan can be active while its tournament contender is eliminated or archived.
- Experiment `decision` can drift from contender lifecycle and decision history.
- Scenario cohorts can reference scenarios from another experiment.
- Evidence indexes are derived from records and can be stale if records are written outside the store.
