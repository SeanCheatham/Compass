use clap::{Parser, Subcommand, ValueEnum};

#[derive(Debug, Parser)]
#[command(name = "compass-engine", version, about = "Compass Rust factory sidecar")]
pub struct Cli {
    #[arg(long, global = true, default_value = ".")]
    pub repo: camino::Utf8PathBuf,

    #[arg(long, global = true, value_enum, default_value_t = OutputFormat::Json)]
    pub format: OutputFormat,

    #[command(subcommand)]
    pub command: Command,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub enum OutputFormat {
    Json,
    Text,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    Ping,
    #[command(name = "workspace-outline")]
    WorkspaceOutline,
}

impl Command {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Ping => "ping",
            Self::WorkspaceOutline => "workspace-outline",
        }
    }
}
