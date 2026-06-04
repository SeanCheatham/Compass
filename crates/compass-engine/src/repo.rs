use anyhow::{anyhow, Context, Result};
use camino::{Utf8Path, Utf8PathBuf};

pub fn canonical_existing_path(start: &Utf8Path) -> Result<Utf8PathBuf> {
    let canonical = std::fs::canonicalize(start)
        .with_context(|| format!("repo path does not exist: {start}"))?;
    Utf8PathBuf::from_path_buf(canonical)
        .map_err(|path| anyhow!("repo path is not valid UTF-8: {}", path.display()))
}

pub fn resolve_repo(start: &Utf8Path) -> Result<Utf8PathBuf> {
    let mut current = canonical_existing_path(start)?;

    if current.is_file() {
        current.pop();
    }

    loop {
        if current.join("Cargo.toml").is_file() {
            return Ok(current);
        }
        if !current.pop() {
            return Err(anyhow!("could not find Cargo.toml above {start}"));
        }
    }
}
