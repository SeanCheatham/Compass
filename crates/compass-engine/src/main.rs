use anyhow::Result;
use clap::Parser;
use compass_engine::cli::{
    CargoCheckArgs, CargoTestArgs, Cli, Command, CoverageArgs, OutputFormat,
};
use compass_engine::output::{EngineAudit, EngineResponse};
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
            println!(
                "{}",
                serde_json::to_string_pretty(&data.with_audit(audit()))
                    .expect("serialize response")
            );
        }
        (OutputFormat::Json, Err(error)) => {
            let response =
                EngineResponse::<serde_json::Value>::error(command_name, vec![error.to_string()])
                    .with_audit(audit());
            println!(
                "{}",
                serde_json::to_string_pretty(&response).expect("serialize error response")
            );
            std::process::exit(1);
        }
        (OutputFormat::Text, Ok(data)) => {
            println!(
                "{}",
                serde_json::to_string_pretty(&data.with_audit(audit()))
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
