use anyhow::{Context, Result};
use camino::{Utf8Path, Utf8PathBuf};
use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Serialize)]
pub struct WorkspaceOutline {
    pub workspace_root: String,
    pub members: Vec<CargoMember>,
    pub edges: Vec<CargoEdge>,
}

#[derive(Debug, Serialize)]
pub struct CargoMember {
    pub name: String,
    pub manifest_path: String,
    pub kind: String,
    pub package_dir: String,
    pub src_root: String,
    pub dependencies: Vec<CargoDependency>,
    pub features: CargoFeatures,
}

#[derive(Debug, Serialize)]
pub struct CargoDependency {
    pub name: String,
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    pub features: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct CargoFeatures {
    pub default: Vec<String>,
    pub named: BTreeMap<String, Vec<String>>,
}

#[derive(Debug, Serialize)]
pub struct CargoEdge {
    pub from: String,
    pub to: String,
    pub dev: bool,
    pub optional: bool,
}

pub fn workspace_outline(repo: &Utf8Path) -> Result<WorkspaceOutline> {
    let output = std::process::Command::new("cargo")
        .arg("metadata")
        .arg("--format-version")
        .arg("1")
        .current_dir(repo)
        .output()
        .context("failed to spawn cargo metadata")?;
    if !output.status.success() {
        anyhow::bail!(
            "cargo metadata failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    let metadata: Value =
        serde_json::from_slice(&output.stdout).context("failed to parse cargo metadata JSON")?;
    let workspace_root = metadata
        .get("workspace_root")
        .and_then(Value::as_str)
        .map(Utf8PathBuf::from)
        .unwrap_or_else(|| repo.to_path_buf());
    let member_ids: BTreeSet<String> = metadata
        .get("workspace_members")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(ToOwned::to_owned)
        .collect();
    let packages = metadata
        .get("packages")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut workspace_names = BTreeSet::new();
    for package in &packages {
        if let Some(id) = package.get("id").and_then(Value::as_str) {
            if member_ids.contains(id) {
                if let Some(name) = package.get("name").and_then(Value::as_str) {
                    workspace_names.insert(name.to_owned());
                }
            }
        }
    }

    let mut members = Vec::new();
    let mut edges = Vec::new();
    for package in packages {
        let id = package
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if !member_ids.is_empty() && !member_ids.contains(id) {
            continue;
        }
        let name = package
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("unknown")
            .to_owned();
        let manifest_path = package
            .get("manifest_path")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let manifest = Utf8Path::new(manifest_path);
        let package_dir = manifest.parent().unwrap_or(repo);
        let targets = package
            .get("targets")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let (kind, src_root) = target_kind_and_src_root(&targets, package_dir);

        let mut dependencies = Vec::new();
        for dep in package
            .get("dependencies")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let dep_name = dep
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("unknown")
                .to_owned();
            let path = dep
                .get("path")
                .and_then(Value::as_str)
                .map(Utf8PathBuf::from);
            let kind = if path.is_some() { "path" } else { "external" }.to_owned();
            let features = dep
                .get("features")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>();
            let optional = dep
                .get("optional")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let dev = dep
                .get("kind")
                .and_then(Value::as_str)
                .map(|value| value == "dev")
                .unwrap_or(false);
            if workspace_names.contains(&dep_name) {
                edges.push(CargoEdge {
                    from: name.clone(),
                    to: dep_name.clone(),
                    dev,
                    optional,
                });
            }
            dependencies.push(CargoDependency {
                name: dep_name,
                kind,
                version: dep
                    .get("req")
                    .and_then(Value::as_str)
                    .filter(|value| !value.is_empty() && *value != "*")
                    .map(ToOwned::to_owned),
                path: path.map(|value| relative_path(repo, &value)),
                features,
            });
        }

        dependencies.sort_by(|a, b| a.name.cmp(&b.name));
        members.push(CargoMember {
            name,
            manifest_path: relative_path(repo, manifest),
            kind,
            package_dir: relative_path(repo, package_dir),
            src_root: relative_path(repo, &src_root),
            dependencies,
            features: parse_features(&package),
        });
    }

    members.sort_by(|a, b| a.name.cmp(&b.name));
    edges.sort_by(|a, b| (&a.from, &a.to).cmp(&(&b.from, &b.to)));
    Ok(WorkspaceOutline {
        workspace_root: relative_path(repo, &workspace_root.join("Cargo.toml")),
        members,
        edges,
    })
}

fn target_kind_and_src_root(targets: &[Value], package_dir: &Utf8Path) -> (String, Utf8PathBuf) {
    let mut selected = targets.first();
    for target in targets {
        let kinds = target
            .get("kind")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .collect::<Vec<_>>();
        if kinds.contains(&"lib") {
            selected = Some(target);
            break;
        }
    }
    if let Some(target) = selected {
        let kind = target
            .get("kind")
            .and_then(Value::as_array)
            .and_then(|values| values.first())
            .and_then(Value::as_str)
            .unwrap_or("unknown")
            .to_owned();
        let src = target
            .get("src_path")
            .and_then(Value::as_str)
            .map(Utf8PathBuf::from)
            .unwrap_or_else(|| package_dir.join("src/lib.rs"));
        return (kind, src.parent().unwrap_or(package_dir).to_path_buf());
    }
    ("unknown".to_owned(), package_dir.join("src"))
}

fn parse_features(package: &Value) -> CargoFeatures {
    let mut named = BTreeMap::new();
    if let Some(features) = package.get("features").and_then(Value::as_object) {
        for (key, value) in features {
            let values = value
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>();
            if key != "default" {
                named.insert(key.clone(), values);
            }
        }
    }
    let default = package
        .get("features")
        .and_then(|features| features.get("default"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();
    CargoFeatures { default, named }
}

fn relative_path(repo: &Utf8Path, path: &Utf8Path) -> String {
    path.strip_prefix(repo)
        .unwrap_or(path)
        .to_string()
        .trim_start_matches("./")
        .to_owned()
}
