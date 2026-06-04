use serde::Serialize;

pub const SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Serialize)]
pub struct EngineResponse<T: Serialize> {
    pub schema_version: u32,
    pub command: String,
    pub ok: bool,
    pub data: Option<T>,
    pub errors: Vec<String>,
}

impl<T: Serialize> EngineResponse<T> {
    pub fn ok(command: impl Into<String>, data: T) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            command: command.into(),
            ok: true,
            data: Some(data),
            errors: Vec::new(),
        }
    }

    pub fn error(command: impl Into<String>, errors: Vec<String>) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            command: command.into(),
            ok: false,
            data: None,
            errors,
        }
    }
}
