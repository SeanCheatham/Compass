use serde::Serialize;

pub const SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Serialize)]
pub struct EngineResponse<T: Serialize> {
    pub schema_version: u32,
    pub command: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audit: Option<EngineAudit>,
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

impl<T: Serialize> EngineResponse<T> {
    pub fn ok(command: impl Into<String>, data: T) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            command: command.into(),
            ok: true,
            audit: None,
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
            data: None,
            errors,
        }
    }

    pub fn with_audit(mut self, audit: EngineAudit) -> Self {
        self.audit = Some(audit);
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
