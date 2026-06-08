use crate::protocol::{settings::AgentRuntimeSettings, vm::SharedVMRoute};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentRunConfig {
    pub repo_path: String,
    pub phase: String,
    pub system_prompt: String,
    pub user_prompt: String,
    pub settings: AgentRuntimeSettings,
    #[serde(default)]
    pub tools: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shared_vm_route: Option<SharedVMRoute>,
    #[serde(default = "default_max_iterations")]
    pub max_iterations: u32,
    #[serde(default = "default_wall_clock_timeout_secs")]
    pub wall_clock_timeout_secs: u64,
}

fn default_max_iterations() -> u32 {
    40
}

fn default_wall_clock_timeout_secs() -> u64 {
    3_600
}
