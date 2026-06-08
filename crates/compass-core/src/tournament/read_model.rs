use super::state_v2::ProductTournamentStateV2;
use serde::Serialize;

#[derive(Clone, Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProductTournamentReadModelSummary {
    pub schema_version: u32,
    pub pain_title: Option<String>,
    pub active_round_id: Option<String>,
    pub active_round_title: Option<String>,
    pub outcome_winner_contender_id: Option<String>,
    pub segment_count: usize,
    pub alternative_count: usize,
    pub contender_count: usize,
    pub round_count: usize,
    pub decision_count: usize,
    pub contenders: Vec<ProductTournamentContenderSummary>,
    pub rounds: Vec<ProductTournamentRoundSummary>,
    pub validation_errors: Vec<String>,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProductTournamentContenderSummary {
    pub id: String,
    pub title: String,
    pub lifecycle: String,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProductTournamentRoundSummary {
    pub id: String,
    pub ordinal: i64,
    pub kind: String,
    pub title: String,
    pub lifecycle: String,
    pub contender_count: usize,
}

impl ProductTournamentReadModelSummary {
    pub fn from_state(state: &ProductTournamentStateV2) -> Self {
        let active_round = state.active_round_id.as_ref().and_then(|id| {
            state
                .rounds
                .iter()
                .find(|round| round.id.as_str() == id.as_str())
        });

        Self {
            schema_version: state.schema_version,
            pain_title: state.pain.as_ref().map(|pain| pain.title.clone()),
            active_round_id: state.active_round_id.clone(),
            active_round_title: active_round.map(|round| round.title.clone()),
            outcome_winner_contender_id: state
                .outcome
                .as_ref()
                .map(|outcome| outcome.winner_contender_id.clone()),
            segment_count: state.segments.len(),
            alternative_count: state.alternatives.len(),
            contender_count: state.contenders.len(),
            round_count: state.rounds.len(),
            decision_count: state.decision_log.len(),
            contenders: state
                .contenders
                .iter()
                .map(|contender| ProductTournamentContenderSummary {
                    id: contender.id.clone(),
                    title: contender.title.clone(),
                    lifecycle: contender.lifecycle.clone(),
                })
                .collect(),
            rounds: state
                .rounds
                .iter()
                .map(|round| ProductTournamentRoundSummary {
                    id: round.id.clone(),
                    ordinal: round.ordinal,
                    kind: round.kind.clone(),
                    title: round.title.clone(),
                    lifecycle: round.lifecycle.clone(),
                    contender_count: round.contender_ids.len(),
                })
                .collect(),
            validation_errors: state.validation_errors(),
        }
    }
}
