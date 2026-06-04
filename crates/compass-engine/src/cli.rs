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
    #[command(name = "cargo-check")]
    CargoCheck(CargoCheckArgs),
    #[command(name = "clippy-lint")]
    ClippyLint(CargoCheckArgs),
    #[command(name = "cargo-test")]
    CargoTest(CargoTestArgs),
    #[command(name = "index-rust")]
    IndexRust,
    #[command(name = "schema-contracts")]
    SchemaContracts,
    #[command(name = "coverage-gaps")]
    CoverageGaps(CoverageArgs),
    #[command(name = "visual-verify")]
    VisualVerify,
}

#[derive(Debug, clap::Args)]
pub struct CoverageArgs {
    #[arg(long = "package", short = 'p')]
    pub package: Option<String>,
}

#[derive(Debug, clap::Args)]
pub struct CargoCheckArgs {
    #[arg(long = "package", short = 'p')]
    pub package: Vec<String>,
    #[arg(long)]
    pub all_features: bool,
}

#[derive(Debug, clap::Args)]
pub struct CargoTestArgs {
    #[arg(long = "package", short = 'p')]
    pub package: Vec<String>,
    #[arg(long = "test")]
    pub test_bin: Option<String>,
    #[arg(long = "filter")]
    pub filter: Option<String>,
    #[arg(long)]
    pub all_features: bool,
}

impl Command {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Ping => "ping",
            Self::WorkspaceOutline => "workspace-outline",
            Self::CargoCheck(_) => "cargo-check",
            Self::ClippyLint(_) => "clippy-lint",
            Self::CargoTest(_) => "cargo-test",
            Self::IndexRust => "index-rust",
            Self::SchemaContracts => "schema-contracts",
            Self::CoverageGaps(_) => "coverage-gaps",
            Self::VisualVerify => "visual-verify",
        }
    }
}
