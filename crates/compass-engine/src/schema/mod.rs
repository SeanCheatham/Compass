use anyhow::Result;
use camino::{Utf8Path, Utf8PathBuf};
use regex::Regex;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeSet;
use walkdir::WalkDir;

#[derive(Debug, Serialize)]
pub struct SchemaContractsOutput {
    pub schema_version: u32,
    pub contracts: Vec<SchemaContract>,
}

#[derive(Debug, Serialize)]
pub struct SchemaContract {
    pub schema_path: String,
    pub schema_title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rust_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rust_file: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line: Option<usize>,
    pub confidence: String,
    pub field_mapping: Vec<FieldMapping>,
}

#[derive(Debug, Serialize)]
pub struct FieldMapping {
    pub schema_field: String,
    pub rust_field: String,
}

#[derive(Debug)]
struct RustType {
    name: String,
    file: String,
    line: usize,
    fields: BTreeSet<String>,
}

pub fn schema_contracts(repo: &Utf8Path) -> Result<SchemaContractsOutput> {
    let schemas_dir = repo.join("schemas");
    if !schemas_dir.exists() {
        return Ok(SchemaContractsOutput {
            schema_version: 1,
            contracts: Vec::new(),
        });
    }
    let rust_types = scan_rust_types(repo)?;
    let mut contracts = Vec::new();
    for entry in WalkDir::new(&schemas_dir)
        .into_iter()
        .filter_map(|entry| entry.ok())
    {
        if !entry.file_type().is_file()
            || entry.path().extension().and_then(|e| e.to_str()) != Some("json")
        {
            continue;
        }
        let path = Utf8PathBuf::from_path_buf(entry.path().to_path_buf())
            .map_err(|path| anyhow::anyhow!("non-UTF8 path: {}", path.display()))?;
        let data = std::fs::read_to_string(&path)?;
        let json: Value = serde_json::from_str(&data)?;
        let relative = relative_path(repo, &path);
        let title = json
            .get("title")
            .or_else(|| json.get("$id"))
            .and_then(Value::as_str)
            .map(schema_title_from_value)
            .unwrap_or_else(|| schema_title_from_value(path.file_stem().unwrap_or("schema")));
        let fields = schema_fields(&json);
        let best = best_match(&title, &fields, &rust_types);
        contracts.push(match best {
            Some((rust, confidence, mapping)) => SchemaContract {
                schema_path: relative,
                schema_title: title,
                rust_type: Some(rust.name.clone()),
                rust_file: Some(rust.file.clone()),
                line: Some(rust.line),
                confidence,
                field_mapping: mapping,
            },
            None => SchemaContract {
                schema_path: relative,
                schema_title: title,
                rust_type: None,
                rust_file: None,
                line: None,
                confidence: "low".to_owned(),
                field_mapping: Vec::new(),
            },
        });
    }
    contracts.sort_by(|a, b| a.schema_path.cmp(&b.schema_path));
    Ok(SchemaContractsOutput {
        schema_version: 1,
        contracts,
    })
}

fn scan_rust_types(repo: &Utf8Path) -> Result<Vec<RustType>> {
    let type_regex =
        Regex::new(r"^\s*(?:pub\s+)?(struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)").unwrap();
    let field_regex = Regex::new(r"^\s*(?:pub\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:").unwrap();
    let mut types = Vec::new();
    for entry in WalkDir::new(repo)
        .into_iter()
        .filter_map(|entry| entry.ok())
    {
        if !entry.file_type().is_file()
            || entry.path().extension().and_then(|e| e.to_str()) != Some("rs")
        {
            continue;
        }
        let path = Utf8PathBuf::from_path_buf(entry.path().to_path_buf())
            .map_err(|path| anyhow::anyhow!("non-UTF8 path: {}", path.display()))?;
        if relative_path(repo, &path).contains("/target/") {
            continue;
        }
        let source = std::fs::read_to_string(&path)?;
        let lines = source.lines().collect::<Vec<_>>();
        for (index, line) in lines.iter().enumerate() {
            if let Some(captures) = type_regex.captures(line) {
                let name = captures.get(2).unwrap().as_str().to_owned();
                let mut fields = BTreeSet::new();
                for field_line in lines.iter().skip(index + 1).take(80) {
                    if field_line.contains('}') {
                        break;
                    }
                    if let Some(field) = field_regex.captures(field_line) {
                        fields.insert(field.get(1).unwrap().as_str().to_owned());
                    }
                }
                types.push(RustType {
                    name,
                    file: relative_path(repo, &path),
                    line: index + 1,
                    fields,
                });
            }
        }
    }
    Ok(types)
}

fn best_match<'a>(
    title: &str,
    fields: &BTreeSet<String>,
    rust_types: &'a [RustType],
) -> Option<(&'a RustType, String, Vec<FieldMapping>)> {
    let normalized_title = normalize_name(title);
    let mut best: Option<(&RustType, usize, Vec<FieldMapping>)> = None;
    for rust in rust_types {
        let mut score = 0;
        if normalize_name(&rust.name) == normalized_title {
            score += 100;
        }
        let mapping = fields
            .intersection(&rust.fields)
            .map(|field| FieldMapping {
                schema_field: field.clone(),
                rust_field: field.clone(),
            })
            .collect::<Vec<_>>();
        score += mapping.len() * 10;
        if score > best.as_ref().map(|(_, s, _)| *s).unwrap_or(0) {
            best = Some((rust, score, mapping));
        }
    }
    best.map(|(rust, score, mapping)| {
        let confidence = if score >= 100 {
            "high"
        } else if score >= 20 {
            "medium"
        } else {
            "low"
        }
        .to_owned();
        (rust, confidence, mapping)
    })
}

fn schema_fields(json: &Value) -> BTreeSet<String> {
    json.get("properties")
        .and_then(Value::as_object)
        .map(|properties| properties.keys().cloned().collect())
        .unwrap_or_default()
}

fn schema_title_from_value(value: &str) -> String {
    let stem = value.rsplit('/').next().unwrap_or(value);
    stem.trim_end_matches(".schema")
        .trim_end_matches(".json")
        .to_owned()
}

fn normalize_name(value: &str) -> String {
    value
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

fn relative_path(repo: &Utf8Path, path: &Utf8Path) -> String {
    path.strip_prefix(repo).unwrap_or(path).to_string()
}
