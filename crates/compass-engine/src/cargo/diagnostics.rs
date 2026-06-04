use camino::Utf8Path;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeSet;

pub const MAX_DIAGNOSTICS: usize = 50;
const MAX_RENDERED_CHARS: usize = 500;

#[derive(Debug, Clone, Serialize)]
pub struct Diagnostic {
    pub level: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub package: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub column: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rendered: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct DiagnosticSummary {
    pub errors: usize,
    pub warnings: usize,
    pub crates_affected: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct DiagnosticRun {
    pub exit_code: i32,
    pub diagnostics: Vec<Diagnostic>,
    pub summary: DiagnosticSummary,
}

pub fn parse_json_messages(stdout: &str, repo: &Utf8Path) -> (Vec<Diagnostic>, DiagnosticSummary) {
    let mut diagnostics = Vec::new();
    let mut crates = BTreeSet::new();
    for line in stdout.lines() {
        if diagnostics.len() >= MAX_DIAGNOSTICS {
            break;
        }
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if value.get("reason").and_then(Value::as_str) != Some("compiler-message") {
            continue;
        }
        let message = &value["message"];
        let level = message
            .get("level")
            .and_then(Value::as_str)
            .unwrap_or("note")
            .to_owned();
        let package = value
            .get("package_id")
            .and_then(Value::as_str)
            .and_then(package_name_from_id)
            .map(ToOwned::to_owned);
        if let Some(package) = &package {
            crates.insert(package.clone());
        }
        let (file, line, column, label) = primary_span(message, repo);
        diagnostics.push(Diagnostic {
            level,
            code: message
                .get("code")
                .and_then(|code| code.get("code"))
                .and_then(Value::as_str)
                .map(ToOwned::to_owned),
            message: message
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_owned(),
            package,
            file,
            line,
            column,
            label,
            rendered: message
                .get("rendered")
                .and_then(Value::as_str)
                .map(truncate_rendered),
        });
    }
    let errors = diagnostics
        .iter()
        .filter(|diagnostic| diagnostic.level == "error")
        .count();
    let warnings = diagnostics
        .iter()
        .filter(|diagnostic| diagnostic.level == "warning")
        .count();
    (
        diagnostics,
        DiagnosticSummary {
            errors,
            warnings,
            crates_affected: crates.into_iter().collect(),
        },
    )
}

fn primary_span(
    message: &Value,
    repo: &Utf8Path,
) -> (Option<String>, Option<u64>, Option<u64>, Option<String>) {
    let spans = message
        .get("spans")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let span = spans
        .iter()
        .find(|span| span.get("is_primary").and_then(Value::as_bool) == Some(true))
        .or_else(|| spans.first());
    let Some(span) = span else {
        return (None, None, None, None);
    };
    let file = span
        .get("file_name")
        .and_then(Value::as_str)
        .map(|path| relative_path(repo, Utf8Path::new(path)));
    let line = span.get("line_start").and_then(Value::as_u64);
    let column = span.get("column_start").and_then(Value::as_u64);
    let label = span
        .get("label")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    (file, line, column, label)
}

fn package_name_from_id(id: &str) -> Option<&str> {
    id.split(' ').next()
}

fn relative_path(repo: &Utf8Path, path: &Utf8Path) -> String {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        repo.join(path)
    };
    absolute.strip_prefix(repo).unwrap_or(&absolute).to_string()
}

fn truncate_rendered(value: &str) -> String {
    if value.chars().count() <= MAX_RENDERED_CHARS {
        return value.to_owned();
    }
    let mut truncated = value.chars().take(MAX_RENDERED_CHARS).collect::<String>();
    truncated.push_str("\n[truncated]");
    truncated
}

#[derive(Debug, Serialize)]
pub struct CargoTestFailure {
    pub test_name: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line: Option<u64>,
}

#[derive(Debug, Serialize)]
pub struct CargoTestRun {
    pub exit_code: i32,
    pub passed: usize,
    pub failed: usize,
    pub failures: Vec<CargoTestFailure>,
}

pub fn parse_test_output(exit_code: i32, stdout: &str, stderr: &str) -> CargoTestRun {
    let combined = format!("{stdout}\n{stderr}");
    let mut passed = 0;
    let mut failures = Vec::new();
    let mut current_failure: Option<String> = None;
    for line in combined.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("test ") && trimmed.ends_with(" ... ok") {
            passed += 1;
        } else if trimmed.starts_with("test ") && trimmed.ends_with(" ... FAILED") {
            let name = trimmed
                .trim_start_matches("test ")
                .trim_end_matches(" ... FAILED")
                .to_owned();
            current_failure = Some(name.clone());
            failures.push(CargoTestFailure {
                test_name: name,
                message: "test failed".to_owned(),
                file: None,
                line: None,
            });
        } else if let Some(rest) = trimmed.strip_prefix("thread '") {
            if let Some((name, _)) = rest.split_once("' panicked at ") {
                current_failure = Some(name.to_owned());
            }
        } else if trimmed.contains("panicked at ") {
            if let Some(name) = &current_failure {
                if let Some(last) = failures
                    .iter_mut()
                    .rev()
                    .find(|failure| &failure.test_name == name)
                {
                    last.message = trimmed.to_owned();
                }
            }
        }
    }
    CargoTestRun {
        exit_code,
        passed,
        failed: failures.len(),
        failures,
    }
}
