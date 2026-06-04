use anyhow::Result;
use clap::Parser;
use compass_engine::cli::{
    CargoCheckArgs, CargoTestArgs, Cli, Command, CoverageArgs, OutputFormat,
};
use compass_engine::output::{EngineAudit, EngineResponse, RepairHint};
use std::time::Instant;

fn main() {
    let cli = Cli::parse();
    let command_name = cli.command.name();
    let started = Instant::now();
    let audit_argv = audit_argv(&cli.command);
    let result = run(&cli);
    let audit = || {
        EngineAudit::new(
            cli.repo.to_string(),
            audit_argv.clone(),
            started.elapsed().as_millis(),
        )
    };

    match (cli.format, result) {
        (OutputFormat::Json, Ok(data)) => {
            let repair_hints = repair_hints_for_success(&cli.command, data.data.as_ref());
            let response = data.with_audit(audit()).with_repair_hints(repair_hints);
            println!(
                "{}",
                serde_json::to_string_pretty(&response).expect("serialize response")
            );
        }
        (OutputFormat::Json, Err(error)) => {
            let error_text = error.to_string();
            let repair_hints = repair_hints_for_error(&error_text);
            let response =
                EngineResponse::<serde_json::Value>::error(command_name, vec![error_text])
                    .with_audit(audit())
                    .with_repair_hints(repair_hints);
            println!(
                "{}",
                serde_json::to_string_pretty(&response).expect("serialize error response")
            );
            std::process::exit(1);
        }
        (OutputFormat::Text, Ok(data)) => {
            let repair_hints = repair_hints_for_success(&cli.command, data.data.as_ref());
            println!(
                "{}",
                serde_json::to_string_pretty(
                    &data.with_audit(audit()).with_repair_hints(repair_hints),
                )
                .expect("serialize response")
            );
        }
        (OutputFormat::Text, Err(error)) => {
            eprintln!("{error:#}");
            std::process::exit(1);
        }
    }
}

fn audit_argv(command: &Command) -> Option<Vec<String>> {
    match command {
        Command::Ping | Command::IndexRust | Command::SchemaContracts | Command::ScaffoldCheck => {
            None
        }
        Command::WorkspaceOutline => Some(vec![
            "cargo".to_owned(),
            "metadata".to_owned(),
            "--format-version".to_owned(),
            "1".to_owned(),
        ]),
        Command::CargoCheck(args) => Some(cargo_check_argv(args)),
        Command::ClippyLint(args) => Some(clippy_lint_argv(args)),
        Command::CargoTest(args) => Some(cargo_test_argv(args)),
        Command::CoverageGaps(args) => Some(coverage_gaps_argv(args)),
        Command::VisualVerify => Some(
            [
                "cargo",
                "run",
                "-p",
                "xtask",
                "--",
                "visual-verify",
                "--emit-base64",
            ]
            .into_iter()
            .map(ToOwned::to_owned)
            .collect(),
        ),
    }
}

fn cargo_check_argv(args: &CargoCheckArgs) -> Vec<String> {
    let mut argv = strings(["cargo", "check", "--workspace", "--message-format=json"]);
    append_package_args(&mut argv, &args.package);
    if args.all_features {
        argv.push("--all-features".to_owned());
    }
    argv
}

fn clippy_lint_argv(args: &CargoCheckArgs) -> Vec<String> {
    let mut argv = strings([
        "cargo",
        "clippy",
        "--workspace",
        "--all-targets",
        "--message-format=json",
    ]);
    append_package_args(&mut argv, &args.package);
    if args.all_features {
        argv.push("--all-features".to_owned());
    }
    argv.extend(strings(["--", "-D", "warnings"]));
    argv
}

fn cargo_test_argv(args: &CargoTestArgs) -> Vec<String> {
    let mut argv = strings(["cargo", "test", "--workspace"]);
    append_package_args(&mut argv, &args.package);
    if args.all_features {
        argv.push("--all-features".to_owned());
    }
    if let Some(test_bin) = &args.test_bin {
        argv.extend(["--test".to_owned(), test_bin.clone()]);
    }
    if let Some(filter) = &args.filter {
        argv.push(filter.clone());
    }
    argv
}

fn coverage_gaps_argv(args: &CoverageArgs) -> Vec<String> {
    let mut argv = strings(["cargo", "llvm-cov", "--summary-only"]);
    if let Some(package) = &args.package {
        argv.extend(["--package".to_owned(), package.clone()]);
    }
    argv
}

fn append_package_args(argv: &mut Vec<String>, packages: &[String]) {
    for package in packages {
        argv.extend(["--package".to_owned(), package.clone()]);
    }
}

fn strings<const N: usize>(values: [&str; N]) -> Vec<String> {
    values.into_iter().map(ToOwned::to_owned).collect()
}

fn repair_hints_for_error(error: &str) -> Vec<RepairHint> {
    let lower = error.to_ascii_lowercase();
    let mut hints = Vec::new();
    if lower.contains("could not find `cargo.toml`")
        || lower.contains("could not find cargo.toml")
        || lower.contains("root cargo.toml is missing")
    {
        hints.push(RepairHint::new(
            "missing-cargo-manifest",
            "error",
            "Cargo.toml is missing from the repository root.",
            Some("cargo init --lib"),
        ));
    }
    if lower.contains("cargo metadata failed") {
        hints.push(RepairHint::new(
            "cargo-metadata-failed",
            "error",
            "cargo metadata failed; inspect Cargo.toml workspace members and package manifests.",
            Some("cargo metadata --format-version 1"),
        ));
    }
    if lower.contains("cargo-llvm-cov") || lower.contains("llvm-cov") {
        hints.push(RepairHint::new(
            "missing-cargo-llvm-cov",
            "warning",
            "cargo-llvm-cov is not installed or could not run.",
            Some("cargo install cargo-llvm-cov"),
        ));
    }
    if lower.contains("rustfmt") {
        hints.push(RepairHint::new(
            "missing-rustfmt",
            "warning",
            "rustfmt is unavailable for the active Rust toolchain.",
            Some("rustup component add rustfmt"),
        ));
    }
    if lower.contains("clippy") {
        hints.push(RepairHint::new(
            "missing-clippy",
            "warning",
            "clippy is unavailable for the active Rust toolchain.",
            Some("rustup component add clippy"),
        ));
    }
    hints
}

fn repair_hints_for_success(
    command: &Command,
    data: Option<&serde_json::Value>,
) -> Vec<RepairHint> {
    let Some(data) = data else {
        return Vec::new();
    };
    match command {
        Command::ScaffoldCheck => scaffold_repair_hints(data),
        Command::VisualVerify => visual_repair_hints(data),
        _ => Vec::new(),
    }
}

fn scaffold_repair_hints(data: &serde_json::Value) -> Vec<RepairHint> {
    let mut hints = Vec::new();
    let Some(checks) = data.get("checks").and_then(serde_json::Value::as_array) else {
        return hints;
    };
    for check in checks {
        if check.get("status").and_then(serde_json::Value::as_str) != Some("fail") {
            continue;
        }
        let id = check
            .get("id")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default();
        let path = check
            .get("path")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default();
        if id.starts_with("member_") {
            hints.push(RepairHint::new(
                "generated-scaffold-missing-member",
                "error",
                format!("Generated scaffold is missing required member manifest {path}."),
                None::<String>,
            ));
        } else if id == "toolchain_rustfmt" {
            hints.push(RepairHint::new(
                "missing-rustfmt",
                "warning",
                "rust-toolchain.toml does not include rustfmt.",
                Some("rustup component add rustfmt"),
            ));
        } else if id == "toolchain_clippy" {
            hints.push(RepairHint::new(
                "missing-clippy",
                "warning",
                "rust-toolchain.toml does not include clippy.",
                Some("rustup component add clippy"),
            ));
        } else if id == "metadata_present" || id == "metadata_capabilities" {
            hints.push(RepairHint::new(
                "generated-scaffold-metadata-drift",
                "error",
                "Generated scaffold metadata is missing or incomplete.",
                None::<String>,
            ));
        } else if id == "schemas_directory" {
            hints.push(RepairHint::new(
                "generated-scaffold-missing-schemas",
                "error",
                "Scaffold advertises schema contracts but schemas/ is missing.",
                None::<String>,
            ));
        } else if id == "visual_desktop_crate" || id == "desktop_source" {
            hints.push(RepairHint::new(
                "generated-scaffold-missing-desktop",
                "error",
                "Scaffold advertises visual verification but the desktop crate/source is missing.",
                None::<String>,
            ));
        } else if id.starts_with("simulation_") {
            hints.push(RepairHint::new(
                "generated-scaffold-missing-simulation-fixture",
                "error",
                "Scaffold advertises deterministic simulation fixtures but the core or CLI fixture surface is missing.",
                None::<String>,
            ));
        } else if id.starts_with("gui_replay_") {
            hints.push(RepairHint::new(
                "generated-scaffold-missing-gui-replay",
                "error",
                "Scaffold advertises deterministic GUI replay but the semantic replay surface or desktop snapshot hook is missing.",
                None::<String>,
            ));
        }
    }
    dedupe_hints(hints)
}

fn visual_repair_hints(data: &serde_json::Value) -> Vec<RepairHint> {
    if data.get("ok").and_then(serde_json::Value::as_bool) == Some(true) {
        return Vec::new();
    }
    let log_tail = data
        .get("log_tail")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_ascii_lowercase();
    let mut hints = Vec::new();
    if log_tail.contains("readiness") || log_tail.contains("ready") {
        hints.push(RepairHint::new(
            "visual-readiness-missing",
            "error",
            "The visual app did not write its readiness file before timeout.",
            Some("cargo run -p xtask -- visual-verify"),
        ));
    }
    if log_tail.contains("screenshot") || log_tail.contains("viewport") {
        hints.push(RepairHint::new(
            "visual-screenshot-missing",
            "error",
            "The visual app did not write a non-empty screenshot artifact.",
            Some("cargo run -p xtask -- visual-verify --emit-base64"),
        ));
    }
    if log_tail.contains("acknowledgement") || log_tail.contains("ack") {
        hints.push(RepairHint::new(
            "visual-input-ack-missing",
            "error",
            "The visual app did not acknowledge the basic input request.",
            Some("cargo run -p xtask -- visual-verify"),
        ));
    }
    hints
}

fn dedupe_hints(hints: Vec<RepairHint>) -> Vec<RepairHint> {
    let mut seen = std::collections::BTreeSet::new();
    hints
        .into_iter()
        .filter(|hint| seen.insert(hint.id.clone()))
        .collect()
}

fn run(cli: &Cli) -> Result<EngineResponse<serde_json::Value>> {
    let value = match &cli.command {
        Command::Ping => {
            let repo = compass_engine::repo::canonical_existing_path(&cli.repo)?;
            serde_json::to_value(compass_engine::ping(&repo)?)?
        }
        Command::WorkspaceOutline => {
            let repo = compass_engine::repo::resolve_repo(&cli.repo)?;
            serde_json::to_value(compass_engine::workspace_outline::workspace_outline(&repo)?)?
        }
        Command::CargoCheck(args) => {
            let repo = compass_engine::repo::resolve_repo(&cli.repo)?;
            serde_json::to_value(compass_engine::cargo::commands::cargo_check(&repo, args)?)?
        }
        Command::ClippyLint(args) => {
            let repo = compass_engine::repo::resolve_repo(&cli.repo)?;
            serde_json::to_value(compass_engine::cargo::commands::clippy_lint(&repo, args)?)?
        }
        Command::CargoTest(args) => {
            let repo = compass_engine::repo::resolve_repo(&cli.repo)?;
            serde_json::to_value(compass_engine::cargo::commands::cargo_test(&repo, args)?)?
        }
        Command::IndexRust => {
            let repo = compass_engine::repo::resolve_repo(&cli.repo)?;
            serde_json::to_value(compass_engine::index::index_rust(&repo)?)?
        }
        Command::SchemaContracts => {
            let repo = compass_engine::repo::resolve_repo(&cli.repo)?;
            serde_json::to_value(compass_engine::schema::schema_contracts(&repo)?)?
        }
        Command::ScaffoldCheck => {
            let repo = compass_engine::repo::resolve_repo(&cli.repo)?;
            serde_json::to_value(compass_engine::scaffold::scaffold_check(&repo)?)?
        }
        Command::CoverageGaps(args) => {
            let repo = compass_engine::repo::resolve_repo(&cli.repo)?;
            serde_json::to_value(compass_engine::cargo::commands::coverage_gaps(&repo, args)?)?
        }
        Command::VisualVerify => {
            let repo = compass_engine::repo::resolve_repo(&cli.repo)?;
            serde_json::to_value(compass_engine::cargo::commands::visual_verify(&repo)?)?
        }
    };
    Ok(EngineResponse::ok(cli.command.name(), value))
}
