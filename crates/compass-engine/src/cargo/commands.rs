use crate::cargo::diagnostics::{parse_json_messages, parse_test_output, CargoTestRun, DiagnosticRun};
use crate::cli::{CargoCheckArgs, CargoTestArgs};
use anyhow::{Context, Result};
use camino::Utf8Path;

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
