use anyhow::{anyhow, Context, Result};
use glob::glob;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ToolOutput {
    pub ok: bool,
    pub stdout: String,
    pub stderr: String,
    pub exit_code: Option<i32>,
}

pub fn registry() -> Vec<ToolSpec> {
    [
        ("read_file", "Read a UTF-8 file from the workspace"),
        ("write_file", "Write a UTF-8 file inside the workspace"),
        ("glob", "Find files by glob pattern inside the workspace"),
        ("grep", "Search text files inside the workspace"),
        ("bash", "Run a shell command in the workspace"),
    ]
    .into_iter()
    .map(|(name, description)| ToolSpec {
        name: name.to_owned(),
        description: description.to_owned(),
    })
    .collect()
}

pub fn read_file(repo_root: &Path, path: &str) -> Result<String> {
    let path = workspace_path(repo_root, path)?;
    fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))
}

pub fn write_file(repo_root: &Path, path: &str, contents: &str) -> Result<()> {
    let path = workspace_path(repo_root, path)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, contents).with_context(|| format!("writing {}", path.display()))
}

pub fn glob_files(repo_root: &Path, pattern: &str) -> Result<Vec<String>> {
    let root = repo_root
        .canonicalize()
        .unwrap_or_else(|_| repo_root.to_path_buf());
    let full_pattern = root.join(pattern);
    let mut matches = Vec::new();
    for entry in glob(full_pattern.to_string_lossy().as_ref())? {
        let path = entry?;
        if path.is_file() {
            matches.push(relative_display(&root, &path));
        }
    }
    matches.sort();
    Ok(matches)
}

pub fn grep(repo_root: &Path, needle: &str) -> Result<Vec<String>> {
    let mut matches = Vec::new();
    visit_files(repo_root, &mut |path| {
        if let Ok(contents) = fs::read_to_string(path) {
            for (index, line) in contents.lines().enumerate() {
                if line.contains(needle) {
                    matches.push(format!(
                        "{}:{}:{}",
                        relative_display(repo_root, path),
                        index + 1,
                        line
                    ));
                }
            }
        }
        Ok(())
    })?;
    matches.sort();
    Ok(matches)
}

pub fn bash(repo_root: &Path, command: &str) -> Result<ToolOutput> {
    let output = Command::new("/bin/sh")
        .arg("-lc")
        .arg(command)
        .current_dir(repo_root)
        .output()
        .with_context(|| format!("running shell command in {}", repo_root.display()))?;
    Ok(ToolOutput {
        ok: output.status.success(),
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        exit_code: output.status.code(),
    })
}

fn workspace_path(repo_root: &Path, path: &str) -> Result<PathBuf> {
    let relative = Path::new(path);
    if relative.is_absolute()
        || relative
            .components()
            .any(|part| matches!(part, std::path::Component::ParentDir))
    {
        return Err(anyhow!("path must be workspace-relative: {path}"));
    }
    Ok(repo_root.join(relative))
}

fn visit_files(root: &Path, visitor: &mut impl FnMut(&Path) -> Result<()>) -> Result<()> {
    for entry in fs::read_dir(root).with_context(|| format!("reading {}", root.display()))? {
        let entry = entry?;
        let path = entry.path();
        let file_name = entry.file_name();
        if file_name.to_string_lossy().starts_with(".git") {
            continue;
        }
        if path.is_dir() {
            visit_files(&path, visitor)?;
        } else if path.is_file() {
            visitor(&path)?;
        }
    }
    Ok(())
}

fn relative_display(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}
