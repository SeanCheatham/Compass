use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::SCHEMA_VERSION;

#[derive(Debug, Deserialize)]
pub struct DaemonRequest {
    pub schema_version: u32,
    pub id: String,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Debug, Serialize)]
pub struct DaemonResponse {
    pub schema_version: u32,
    pub id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    pub errors: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct DaemonCapabilities {
    pub compassd_version: String,
    pub core_version: String,
    pub schema_version: u32,
    pub methods: Vec<String>,
    pub capabilities: Vec<String>,
}

impl DaemonResponse {
    pub fn ok(id: impl Into<String>, result: impl Serialize) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            id: id.into(),
            ok: true,
            result: Some(serde_json::to_value(result).unwrap_or(Value::Null)),
            errors: Vec::new(),
        }
    }

    pub fn empty_ok(id: impl Into<String>) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            id: id.into(),
            ok: true,
            result: Some(Value::Object(Default::default())),
            errors: Vec::new(),
        }
    }

    pub fn error(id: impl Into<String>, errors: Vec<String>) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            id: id.into(),
            ok: false,
            result: None,
            errors,
        }
    }
}

pub fn supported_methods() -> Vec<String> {
    [
        "ping",
        "shutdown",
        "get_capabilities",
        "tournament_load",
        "tournament_validate",
        "tournament_read_model",
        "agent_tool_list",
        "agent_run_start",
        "agent_run_status",
        "agent_run_cancel",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect()
}

pub fn capabilities(
    compassd_version: impl Into<String>,
    core_version: impl Into<String>,
) -> DaemonCapabilities {
    DaemonCapabilities {
        compassd_version: compassd_version.into(),
        core_version: core_version.into(),
        schema_version: SCHEMA_VERSION,
        methods: supported_methods(),
        capabilities: vec![
            "daemon.lifecycle".to_owned(),
            "daemon.ndjson".to_owned(),
            "schemas.compassd.v1".to_owned(),
            "tournament.read_only".to_owned(),
            "agent.mock_executor".to_owned(),
            "agent.host_tools".to_owned(),
        ],
    }
}
