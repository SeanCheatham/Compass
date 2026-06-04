use serde::Serialize;

pub const SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Serialize)]
pub struct EngineResponse<T: Serialize> {
    pub schema_version: u32,
    pub command: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audit: Option<EngineAudit>,
    pub repair_hints: Vec<RepairHint>,
    pub data: Option<T>,
    pub errors: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct EngineAudit {
    pub repo: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub argv: Option<Vec<String>>,
    pub duration_ms: u128,
    pub toolchain: EngineToolchain,
}

#[derive(Debug, Serialize)]
pub struct EngineToolchain {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rustc: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cargo: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct RepairHint {
    pub id: String,
    pub severity: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub suggested_command: Option<String>,
}

impl<T: Serialize> EngineResponse<T> {
    pub fn ok(command: impl Into<String>, data: T) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            command: command.into(),
            ok: true,
            audit: None,
            repair_hints: Vec::new(),
            data: Some(data),
            errors: Vec::new(),
        }
    }

    pub fn error(command: impl Into<String>, errors: Vec<String>) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            command: command.into(),
            ok: false,
            audit: None,
            repair_hints: Vec::new(),
            data: None,
            errors,
        }
    }

    pub fn with_audit(mut self, audit: EngineAudit) -> Self {
        self.audit = Some(audit);
        self
    }

    pub fn with_repair_hints(mut self, repair_hints: Vec<RepairHint>) -> Self {
        self.repair_hints = repair_hints;
        self
    }
}

impl EngineAudit {
    pub fn new(repo: impl Into<String>, argv: Option<Vec<String>>, duration_ms: u128) -> Self {
        Self {
            repo: repo.into(),
            argv,
            duration_ms,
            toolchain: EngineToolchain::collect(),
        }
    }
}

impl EngineToolchain {
    pub fn collect() -> Self {
        Self {
            rustc: command_version("rustc"),
            cargo: command_version("cargo"),
        }
    }
}

fn command_version(program: &str) -> Option<String> {
    std::process::Command::new(program)
        .arg("--version")
        .output()
        .ok()
        .and_then(|output| {
            if output.status.success() {
                Some(String::from_utf8_lossy(&output.stdout).trim().to_owned())
            } else {
                None
            }
        })
        .filter(|value| !value.is_empty())
}

impl RepairHint {
    pub fn new(
        id: impl Into<String>,
        severity: impl Into<String>,
        message: impl Into<String>,
        suggested_command: Option<impl Into<String>>,
    ) -> Self {
        Self {
            id: id.into(),
            severity: severity.into(),
            message: message.into(),
            suggested_command: suggested_command.map(Into::into),
        }
    }
}
