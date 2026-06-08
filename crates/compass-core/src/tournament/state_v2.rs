use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProductTournamentStateV2 {
    pub schema_version: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pain: Option<TournamentPainV2>,
    #[serde(default)]
    pub segments: Vec<TournamentIdentifiedV2>,
    #[serde(default)]
    pub alternatives: Vec<TournamentIdentifiedV2>,
    #[serde(default)]
    pub contenders: Vec<ProductTournamentContenderV2>,
    #[serde(default)]
    pub rounds: Vec<ProductTournamentRound>,
    #[serde(
        default,
        rename = "activeRoundID",
        skip_serializing_if = "Option::is_none"
    )]
    pub active_round_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub outcome: Option<TournamentOutcomeV2>,
    #[serde(default)]
    #[serde(rename = "decisionLog")]
    pub decision_log: Vec<TournamentDecisionEventV2>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TournamentPainV2 {
    pub id: String,
    #[serde(default)]
    pub title: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TournamentIdentifiedV2 {
    pub id: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProductTournamentContenderV2 {
    pub id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub lifecycle: String,
    #[serde(default)]
    #[serde(rename = "targetSegmentIDs")]
    pub target_segment_ids: Vec<String>,
    #[serde(default)]
    pub updated_at: f64,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProductTournamentRound {
    pub id: String,
    #[serde(default)]
    pub ordinal: i64,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub lifecycle: String,
    #[serde(default)]
    #[serde(rename = "contenderIDs")]
    pub contender_ids: Vec<String>,
    #[serde(default)]
    #[serde(rename = "scenarioCohortIDs")]
    pub scenario_cohort_ids: Vec<String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TournamentOutcomeV2 {
    #[serde(rename = "winnerContenderID")]
    pub winner_contender_id: String,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub completed_at: f64,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TournamentDecisionEventV2 {
    pub id: String,
    #[serde(default)]
    #[serde(rename = "experimentID")]
    pub experiment_id: String,
}

impl ProductTournamentStateV2 {
    pub const SUPPORTED_SCHEMA_VERSION: u32 = 1;

    pub fn empty() -> Self {
        Self {
            schema_version: Self::SUPPORTED_SCHEMA_VERSION,
            pain: None,
            segments: Vec::new(),
            alternatives: Vec::new(),
            contenders: Vec::new(),
            rounds: Vec::new(),
            active_round_id: None,
            outcome: None,
            decision_log: Vec::new(),
        }
    }

    pub fn validation_errors(&self) -> Vec<String> {
        let mut errors = Vec::new();
        duplicate_id_errors(
            "segment",
            self.segments.iter().map(|value| value.id.as_str()),
            &mut errors,
        );
        duplicate_id_errors(
            "alternative",
            self.alternatives.iter().map(|value| value.id.as_str()),
            &mut errors,
        );
        duplicate_id_errors(
            "contender",
            self.contenders.iter().map(|value| value.id.as_str()),
            &mut errors,
        );
        duplicate_id_errors(
            "round",
            self.rounds.iter().map(|value| value.id.as_str()),
            &mut errors,
        );
        duplicate_id_errors(
            "decision",
            self.decision_log.iter().map(|value| value.id.as_str()),
            &mut errors,
        );

        let contender_ids = self
            .contenders
            .iter()
            .map(|value| value.id.as_str())
            .collect::<HashSet<_>>();
        let round_ids = self
            .rounds
            .iter()
            .map(|value| value.id.as_str())
            .collect::<HashSet<_>>();

        if let Some(active_round_id) = self.active_round_id.as_deref() {
            if !round_ids.contains(active_round_id) {
                errors.push(format!(
                    "Active tournament round {active_round_id} is missing from tournament state."
                ));
            }
        } else if self.outcome.is_none() && (!self.contenders.is_empty() || !self.rounds.is_empty())
        {
            errors.push("Unresolved tournament state must include an active round.".to_owned());
        }

        for round in &self.rounds {
            for contender_id in &round.contender_ids {
                if !contender_ids.contains(contender_id.as_str()) {
                    errors.push(format!(
                        "Tournament round {} references unknown contender {}.",
                        round.id, contender_id
                    ));
                }
            }
        }

        for contender in self
            .contenders
            .iter()
            .filter(|value| value.lifecycle == "winner")
        {
            if self.outcome.is_none() {
                errors.push(format!(
                    "Contender {} is marked winner without a completed tournament outcome.",
                    contender.id
                ));
            }
        }

        if let Some(outcome) = &self.outcome {
            if !contender_ids.contains(outcome.winner_contender_id.as_str()) {
                errors.push(format!(
                    "Tournament outcome references unknown winner contender {}.",
                    outcome.winner_contender_id
                ));
            }
        }
        errors
    }
}

fn duplicate_id_errors<'a>(
    entity: &str,
    values: impl Iterator<Item = &'a str>,
    errors: &mut Vec<String>,
) {
    let mut seen = HashSet::new();
    for id in values {
        if !seen.insert(id) {
            errors.push(format!("Duplicate tournament {entity} ID {id}."));
        }
    }
}
