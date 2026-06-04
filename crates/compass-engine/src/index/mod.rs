use anyhow::Result;
use camino::{Utf8Path, Utf8PathBuf};
use regex::Regex;
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use walkdir::WalkDir;

#[derive(Debug, Serialize)]
pub struct RustIndexOutput {
    pub module_index: RustModuleIndex,
    pub trait_index: RustTraitIndex,
    pub warnings: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct RustModuleIndex {
    pub schema_version: u32,
    pub files: BTreeMap<String, RustModuleFile>,
}

#[derive(Debug, Serialize, Clone)]
pub struct RustModuleFile {
    pub module_path: String,
    pub outgoing: Vec<RustModuleEdge>,
    pub incoming: Vec<RustModuleEdge>,
}

#[derive(Debug, Serialize, Clone, Eq, PartialEq, Ord, PartialOrd)]
pub struct RustModuleEdge {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to_file: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_file: Option<String>,
    pub raw: String,
    pub line: usize,
}

#[derive(Debug, Serialize)]
pub struct RustTraitIndex {
    pub schema_version: u32,
    pub impls: Vec<RustTraitImpl>,
    pub by_trait: BTreeMap<String, Vec<String>>,
    pub by_type: BTreeMap<String, Vec<String>>,
}

#[derive(Debug, Serialize, Clone, Eq, PartialEq, Ord, PartialOrd)]
pub struct RustTraitImpl {
    pub trait_name: String,
    pub type_name: String,
    pub file: String,
    pub line: usize,
    pub impl_start_line: usize,
}

#[derive(Debug)]
struct Member {
    name: String,
    src_root: Utf8PathBuf,
}

pub fn index_rust(repo: &Utf8Path) -> Result<RustIndexOutput> {
    let members = workspace_members(repo)?;
    let mut file_to_module = BTreeMap::new();
    let mut crate_roots = BTreeMap::new();
    let mut rust_files = Vec::new();
    for member in &members {
        crate_roots.insert(member.name.replace('-', "_"), member.src_root.join("lib.rs"));
        for entry in WalkDir::new(&member.src_root).into_iter().filter_map(Result::ok) {
            if !entry.file_type().is_file() {
                continue;
            }
            let path = Utf8PathBuf::from_path_buf(entry.path().to_path_buf())
                .map_err(|path| anyhow::anyhow!("non-UTF8 path: {}", path.display()))?;
            if path.extension() != Some("rs") {
                continue;
            }
            let relative = relative_path(repo, &path);
            let module = module_path(member, &path);
            file_to_module.insert(relative.clone(), module);
            rust_files.push((member.name.replace('-', "_"), path, relative));
        }
    }

    let use_regex = Regex::new(r"^\s*(?:pub\s+)?use\s+([^;]+);").expect("use regex");
    let impl_regex = Regex::new(r"\bimpl\s+([A-Za-z_][A-Za-z0-9_:]*)\s+for\s+([A-Za-z_][A-Za-z0-9_:]*)")
        .expect("impl regex");
    let mut files: BTreeMap<String, RustModuleFile> = BTreeMap::new();
    let mut incoming: BTreeMap<String, Vec<RustModuleEdge>> = BTreeMap::new();
    let mut impls = Vec::new();
    let mut warnings = Vec::new();

    for (crate_name, path, relative) in rust_files {
        let source = match std::fs::read_to_string(&path) {
            Ok(source) => source,
            Err(error) => {
                warnings.push(format!("could not read {relative}: {error}"));
                continue;
            }
        };
        let mut outgoing = Vec::new();
        for (index, line) in source.lines().enumerate() {
            let line_number = index + 1;
            if let Some(captures) = use_regex.captures(line) {
                let raw_path = captures.get(1).map(|m| m.as_str()).unwrap_or("").trim();
                let raw = line.trim().to_owned();
                let target = resolve_use(repo, &members, &crate_roots, &crate_name, raw_path);
                let edge = RustModuleEdge {
                    to_file: target.clone(),
                    from_file: None,
                    raw,
                    line: line_number,
                };
                if let Some(target) = target {
                    incoming.entry(target).or_default().push(RustModuleEdge {
                        to_file: None,
                        from_file: Some(relative.clone()),
                        raw: edge.raw.clone(),
                        line: line_number,
                    });
                }
                outgoing.push(edge);
            }
            if let Some(captures) = impl_regex.captures(line) {
                let trait_name = captures.get(1).unwrap().as_str().rsplit("::").next().unwrap().to_owned();
                let type_name = captures.get(2).unwrap().as_str().rsplit("::").next().unwrap().to_owned();
                impls.push(RustTraitImpl {
                    trait_name,
                    type_name,
                    file: relative.clone(),
                    line: line_number,
                    impl_start_line: line_number,
                });
            }
        }
        files.insert(relative.clone(), RustModuleFile {
            module_path: file_to_module.get(&relative).cloned().unwrap_or(relative),
            outgoing,
            incoming: Vec::new(),
        });
    }

    for (target, mut edges) in incoming {
        edges.sort();
        if let Some(file) = files.get_mut(&target) {
            file.incoming = edges;
        }
    }
    impls.sort();
    let mut by_trait: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut by_type: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for item in &impls {
        by_trait.entry(item.trait_name.clone()).or_default().insert(item.type_name.clone());
        by_type.entry(item.type_name.clone()).or_default().insert(item.trait_name.clone());
    }
    Ok(RustIndexOutput {
        module_index: RustModuleIndex { schema_version: 1, files },
        trait_index: RustTraitIndex {
            schema_version: 1,
            impls,
            by_trait: by_trait.into_iter().map(|(k, v)| (k, v.into_iter().collect())).collect(),
            by_type: by_type.into_iter().map(|(k, v)| (k, v.into_iter().collect())).collect(),
        },
        warnings,
    })
}

fn workspace_members(repo: &Utf8Path) -> Result<Vec<Member>> {
    let outline = crate::workspace_outline::workspace_outline(repo)?;
    Ok(outline
        .members
        .into_iter()
        .map(|member| Member {
            name: member.name,
            src_root: repo.join(member.src_root),
        })
        .collect())
}

fn module_path(member: &Member, path: &Utf8Path) -> String {
    let crate_name = member.name.replace('-', "_");
    let relative = path.strip_prefix(&member.src_root).unwrap_or(path);
    if relative == Utf8Path::new("lib.rs") || relative == Utf8Path::new("main.rs") {
        return crate_name;
    }
    let mut parts = vec![crate_name];
    for component in relative.with_extension("").components() {
        let value = component.as_str();
        if value != "mod" {
            parts.push(value.to_owned());
        }
    }
    parts.join("::")
}

fn resolve_use(
    repo: &Utf8Path,
    members: &[Member],
    crate_roots: &BTreeMap<String, Utf8PathBuf>,
    current_crate: &str,
    raw_path: &str,
) -> Option<String> {
    let cleaned = raw_path
        .trim()
        .trim_start_matches("crate::")
        .split("::")
        .next()
        .unwrap_or("");
    let target_crate = if raw_path.starts_with("crate::") || raw_path.starts_with("self::") || raw_path.starts_with("super::") {
        current_crate
    } else {
        cleaned
    };
    if let Some(root) = crate_roots.get(target_crate) {
        return Some(relative_path(repo, root));
    }
    members
        .iter()
        .find(|member| member.name.replace('-', "_") == target_crate)
        .map(|member| relative_path(repo, &member.src_root.join("lib.rs")))
}

fn relative_path(repo: &Utf8Path, path: &Utf8Path) -> String {
    path.strip_prefix(repo).unwrap_or(path).to_string()
}
