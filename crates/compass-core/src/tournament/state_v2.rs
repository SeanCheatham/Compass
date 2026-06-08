use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProductTournamentStateV2 {
    pub schema_version: u32,
    #[serde(default)]
    pub tournament_id: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub rounds: Vec<ProductTournamentRound>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProductTournamentRound {
    pub id: String,
    pub status: String,
    #[serde(default)]
    pub contenders: Vec<ProductTournamentContender>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProductTournamentContender {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub score: Option<f64>,
}
