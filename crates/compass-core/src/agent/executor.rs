use super::run::AgentRunConfig;
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentRunStartResult {
    pub run_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentRunStatus {
    pub run_id: String,
    pub phase: String,
    pub status: AgentRunLifecycle,
    pub iteration: u32,
    pub elapsed_ms: u128,
    pub result_json: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum AgentRunLifecycle {
    Running,
    Completed,
    Cancelled,
    Failed,
}

pub fn start_mock_run(config: AgentRunConfig) -> (AgentRunStartResult, AgentRunStatus) {
    let run_id = format!("agent-run-{}", unique_suffix());
    let result = AgentRunStartResult {
        run_id: run_id.clone(),
    };
    let status = AgentRunStatus {
        run_id,
        phase: config.phase,
        status: AgentRunLifecycle::Completed,
        iteration: 0,
        elapsed_ms: 0,
        result_json: Some(
            serde_json::json!({
                "mode": "mock",
                "toolCount": config.tools.len(),
                "repoPath": config.repo_path
            })
            .to_string(),
        ),
    };
    (result, status)
}

fn unique_suffix() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
}
