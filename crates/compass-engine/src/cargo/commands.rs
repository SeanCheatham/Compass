use crate::cargo::diagnostics::{parse_json_messages, parse_test_output, CargoTestRun, DiagnosticRun};
use crate::cli::{CargoCheckArgs, CargoTestArgs, CoverageArgs};
use anyhow::{Context, Result};
use camino::Utf8Path;
use serde::Serialize;

pub fn cargo_check(repo: &Utf8Path, args: &CargoCheckArgs) -> Result<DiagnosticRun> {
    let mut command = std::process::Command::new("cargo");
    command
        .arg("check")
        .arg("--workspace")
        .arg("--message-format=json");
    append_package_args(&mut command, &args.package);
    if args.all_features {
        command.arg("--all-features");
    }
    run_diagnostic_command(repo, command)
}

pub fn clippy_lint(repo: &Utf8Path, args: &CargoCheckArgs) -> Result<DiagnosticRun> {
    let mut command = std::process::Command::new("cargo");
    command
        .arg("clippy")
        .arg("--workspace")
        .arg("--all-targets")
        .arg("--message-format=json");
    append_package_args(&mut command, &args.package);
    if args.all_features {
        command.arg("--all-features");
    }
    command.arg("--").arg("-D").arg("warnings");
    run_diagnostic_command(repo, command)
}

pub fn cargo_test(repo: &Utf8Path, args: &CargoTestArgs) -> Result<CargoTestRun> {
    let mut command = std::process::Command::new("cargo");
    command.arg("test").arg("--workspace");
    append_package_args(&mut command, &args.package);
    if args.all_features {
        command.arg("--all-features");
    }
    if let Some(test_bin) = &args.test_bin {
        command.arg("--test").arg(test_bin);
    }
    if let Some(filter) = &args.filter {
        command.arg(filter);
    }
    let output = command
        .current_dir(repo)
        .env("PATH", cargo_path())
        .output()
        .context("failed to spawn cargo test")?;
    Ok(parse_test_output(
        output.status.code().unwrap_or(1),
        &String::from_utf8_lossy(&output.stdout),
        &String::from_utf8_lossy(&output.stderr),
    ))
}

#[derive(Debug, Serialize)]
pub struct CoverageGaps {
    pub overall_line_percent: f64,
    pub files: Vec<CoverageFile>,
    pub log_tail: String,
}

#[derive(Debug, Serialize)]
pub struct CoverageFile {
    pub path: String,
    pub line_percent: f64,
    pub uncovered_lines: Vec<u64>,
}

pub fn coverage_gaps(repo: &Utf8Path, args: &CoverageArgs) -> Result<CoverageGaps> {
    let mut command = std::process::Command::new("cargo");
    command.arg("llvm-cov").arg("--summary-only");
    if let Some(package) = &args.package {
        command.arg("--package").arg(package);
    }
    let output = command.current_dir(repo).env("PATH", cargo_path()).output();
    let output = match output {
        Ok(output) => output,
        Err(error) => anyhow::bail!("failed to spawn cargo llvm-cov: {error}"),
    };
    if !output.status.success() {
        let text = String::from_utf8_lossy(&output.stderr);
        if text.contains("no such command") || text.contains("llvm-cov") {
            anyhow::bail!("cargo-llvm-cov is not installed or could not run: {}", tail(&text, 800));
        }
    }
    let combined = format!(
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(CoverageGaps {
        overall_line_percent: parse_overall_percent(&combined),
        files: Vec::new(),
        log_tail: tail(&combined, 1200),
    })
}

#[derive(Debug, Serialize)]
pub struct VisualVerifyResult {
    pub ok: bool,
    pub screenshot_path: Option<String>,
    pub log_tail: String,
}

pub fn visual_verify(repo: &Utf8Path) -> Result<VisualVerifyResult> {
    let output = std::process::Command::new("cargo")
        .args(["run", "-p", "xtask", "--", "visual-verify", "--emit-base64"])
        .current_dir(repo)
        .env("PATH", cargo_path())
        .output()
        .context("failed to spawn visual verify xtask")?;
    let combined = format!(
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let screenshot_path = extract_screenshot(&combined).and_then(|data| {
        let dir = repo.join(".compass/visual-verify");
        std::fs::create_dir_all(&dir).ok()?;
        let path = dir.join("latest.png");
        std::fs::write(&path, data).ok()?;
        Some(path.to_string())
    });
    Ok(VisualVerifyResult {
        ok: output.status.success(),
        screenshot_path,
        log_tail: tail(&redact_screenshot(&combined), 4000),
    })
}

fn run_diagnostic_command(repo: &Utf8Path, mut command: std::process::Command) -> Result<DiagnosticRun> {
    let output = command
        .current_dir(repo)
        .env("PATH", cargo_path())
        .output()
        .context("failed to spawn cargo diagnostic command")?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let (diagnostics, summary) = parse_json_messages(&stdout, repo);
    Ok(DiagnosticRun {
        exit_code: output.status.code().unwrap_or(1),
        diagnostics,
        summary,
    })
}

fn append_package_args(command: &mut std::process::Command, packages: &[String]) {
    for package in packages {
        command.arg("--package").arg(package);
    }
}

fn cargo_path() -> String {
    let existing = std::env::var("PATH").unwrap_or_default();
    let home = std::env::var("HOME").unwrap_or_default();
    if home.is_empty() {
        existing
    } else {
        format!("{home}/.cargo/bin:{existing}")
    }
}

fn parse_overall_percent(output: &str) -> f64 {
    for line in output.lines().rev() {
        if !line.to_ascii_lowercase().contains("line") && !line.contains('%') {
            continue;
        }
        for token in line.split_whitespace().rev() {
            if let Ok(percent) = token.trim_end_matches('%').parse::<f64>() {
                return percent;
            }
        }
    }
    0.0
}

fn extract_screenshot(output: &str) -> Option<Vec<u8>> {
    let begin = "COMPASS_VISUAL_SCREENSHOT_BASE64_BEGIN";
    let end = "COMPASS_VISUAL_SCREENSHOT_BASE64_END";
    let start = output.find(begin)? + begin.len();
    let rest = &output[start..];
    let finish = rest.find(end)?;
    let encoded = rest[..finish].chars().filter(|ch| !ch.is_whitespace()).collect::<String>();
    base64_decode(&encoded)
}

fn redact_screenshot(output: &str) -> String {
    let begin = "COMPASS_VISUAL_SCREENSHOT_BASE64_BEGIN";
    let end = "COMPASS_VISUAL_SCREENSHOT_BASE64_END";
    let Some(start) = output.find(begin) else { return output.to_owned() };
    let Some(relative_end) = output[start..].find(end) else { return output.to_owned() };
    let finish = start + relative_end + end.len();
    format!("{}{}\n<base64 screenshot omitted>\n{}{}", &output[..start], begin, end, &output[finish..])
}

fn tail(value: &str, max_chars: usize) -> String {
    let count = value.chars().count();
    if count <= max_chars {
        return value.to_owned();
    }
    value.chars().skip(count - max_chars).collect()
}

fn base64_decode(input: &str) -> Option<Vec<u8>> {
    const TABLE: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::new();
    let mut buffer = 0u32;
    let mut bits = 0u8;
    for byte in input.bytes() {
        if byte == b'=' {
            break;
        }
        let value = TABLE.iter().position(|candidate| *candidate == byte)? as u32;
        buffer = (buffer << 6) | value;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((buffer >> bits) & 0xff) as u8);
        }
    }
    Some(out)
}
