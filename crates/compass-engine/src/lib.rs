pub mod cli;
pub mod output;
pub mod repo;
pub mod workspace_outline;

use anyhow::Result;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct PingData {
    pub version: &'static str,
    pub rustc: Option<String>,
    pub repo: String,
}

pub fn ping(repo: &camino::Utf8Path) -> Result<PingData> {
    let rustc = std::process::Command::new("rustc")
        .arg("--version")
        .output()
        .ok()
        .and_then(|output| {
            if output.status.success() {
                Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
            } else {
                None
            }
        })
        .filter(|value| !value.is_empty());

    Ok(PingData {
        version: env!("CARGO_PKG_VERSION"),
        rustc,
        repo: repo.to_string(),
    })
}
