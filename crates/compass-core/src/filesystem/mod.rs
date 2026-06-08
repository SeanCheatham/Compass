use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::time::UNIX_EPOCH;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FileStat {
    pub is_file: bool,
    pub is_dir: bool,
    pub len: u64,
    pub modified_unix_secs: Option<u64>,
}

pub trait AgentFilesystem: Send + Sync {
    fn read_file(&self, path: &Path) -> Result<Vec<u8>>;
    fn write_file(&self, path: &Path, data: &[u8]) -> Result<()>;
    fn stat(&self, path: &Path) -> Result<FileStat>;
}

#[derive(Clone, Debug, Default)]
pub struct HostFilesystem;

impl AgentFilesystem for HostFilesystem {
    fn read_file(&self, path: &Path) -> Result<Vec<u8>> {
        Ok(fs::read(path)?)
    }

    fn write_file(&self, path: &Path, data: &[u8]) -> Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, data)?;
        Ok(())
    }

    fn stat(&self, path: &Path) -> Result<FileStat> {
        let metadata = fs::metadata(path)?;
        Ok(FileStat {
            is_file: metadata.is_file(),
            is_dir: metadata.is_dir(),
            len: metadata.len(),
            modified_unix_secs: metadata
                .modified()
                .ok()
                .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                .map(|value| value.as_secs()),
        })
    }
}
