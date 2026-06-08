use super::state_v2::ProductTournamentStateV2;
use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TournamentWorkspaceStore {
    pub repo_root: PathBuf,
}

impl TournamentWorkspaceStore {
    pub fn new(repo_root: impl AsRef<Path>) -> Self {
        Self {
            repo_root: repo_root.as_ref().to_path_buf(),
        }
    }

    pub fn tournament_dir(&self) -> PathBuf {
        self.repo_root.join(".compass").join("tournament")
    }

    pub fn state_path(&self) -> PathBuf {
        self.tournament_dir().join("state.json")
    }

    pub fn read_state(&self) -> Result<ProductTournamentStateV2> {
        let path = self.state_path();
        if !path.exists() {
            return Ok(ProductTournamentStateV2::empty());
        }
        let data = fs::read(&path).with_context(|| format!("reading {}", path.display()))?;
        if data.is_empty() {
            return Ok(ProductTournamentStateV2::empty());
        }
        serde_json::from_slice(&data)
            .with_context(|| format!("decoding tournament state at {}", path.display()))
    }

    pub fn validate(&self) -> Result<TournamentValidation> {
        let state = self.read_state()?;
        let errors = state.validation_errors();
        Ok(TournamentValidation {
            ok: errors.is_empty(),
            state_path: self.state_path().to_string_lossy().to_string(),
            errors,
        })
    }
}

#[derive(Clone, Debug, serde::Serialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TournamentValidation {
    pub ok: bool,
    pub state_path: String,
    pub errors: Vec<String>,
}
