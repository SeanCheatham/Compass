use anyhow::Result;
use clap::Parser;
use compass_engine::cli::{Cli, Command, OutputFormat};
use compass_engine::output::EngineResponse;

fn main() {
    let cli = Cli::parse();
    let command_name = cli.command.name();
    let result = run(&cli);

    match (cli.format, result) {
        (OutputFormat::Json, Ok(data)) => {
            println!("{}", serde_json::to_string_pretty(&data).expect("serialize response"));
        }
        (OutputFormat::Json, Err(error)) => {
            let response = EngineResponse::<serde_json::Value>::error(
                command_name,
                vec![error.to_string()],
            );
            println!(
                "{}",
                serde_json::to_string_pretty(&response).expect("serialize error response")
            );
            std::process::exit(1);
        }
        (OutputFormat::Text, Ok(data)) => {
            println!("{}", serde_json::to_string_pretty(&data).expect("serialize response"));
        }
        (OutputFormat::Text, Err(error)) => {
            eprintln!("{error:#}");
            std::process::exit(1);
        }
    }
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
