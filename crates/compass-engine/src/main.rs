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
    };
    Ok(EngineResponse::ok(cli.command.name(), value))
}
