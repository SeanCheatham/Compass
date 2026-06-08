use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CompassWorkspacePaths {
    pub repo_root: PathBuf,
    pub compass_dir: PathBuf,
    pub product_tournament_dir: PathBuf,
    pub runtime_settings: PathBuf,
}

impl CompassWorkspacePaths {
    pub fn new(repo_root: impl AsRef<Path>) -> Self {
        let repo_root = repo_root.as_ref().to_path_buf();
        let compass_dir = repo_root.join(".compass");
        Self {
            product_tournament_dir: compass_dir.join("product-tournament"),
            runtime_settings: compass_dir.join("runtime-settings.json"),
            compass_dir,
            repo_root,
        }
    }
}
