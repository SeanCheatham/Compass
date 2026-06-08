use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SharedVMRoute {
    pub ssh_destination: String,
    pub host_worktree_url: String,
    pub guest_workspace_path: String,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub environment_variables: BTreeMap<String, String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub identity_file: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub known_hosts_file: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub exchange_repo_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub git_remote_url: Option<String>,
}
