use anyhow::Result;
use camino::Utf8Path;
use serde::Serialize;
use std::collections::BTreeMap;

const METADATA_PATH: &str = "compass-scaffold.toml";
const REQUIRED_MEMBERS: &[&str] = &[
    "crates/app-core",
    "crates/app-cli",
    "crates/app-desktop",
    "xtask",
];

#[derive(Debug, Serialize)]
pub struct ScaffoldCheckResult {
    pub status: CheckStatus,
    pub scaffold_version: Option<u32>,
    pub capabilities: ScaffoldCapabilities,
    pub checks: Vec<ScaffoldCheck>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum CheckStatus {
    Pass,
    Warn,
    Fail,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
pub struct ScaffoldCapabilities {
    pub xtask_verify: bool,
    pub visual_verify: bool,
    pub schema_contracts: bool,
    pub desktop_handshake: bool,
    pub simulation_fixtures: bool,
    pub gui_replay: bool,
}

#[derive(Debug, Serialize)]
pub struct ScaffoldCheck {
    pub id: String,
    pub status: CheckStatus,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
}

#[derive(Debug)]
struct ParsedMetadata {
    schema_version: Option<u32>,
    scaffold_version: Option<u32>,
    profile: Option<String>,
    capabilities: ScaffoldCapabilities,
}

pub fn scaffold_check(repo: &Utf8Path) -> Result<ScaffoldCheckResult> {
    let mut checks = Vec::new();
    let metadata = read_metadata(repo, &mut checks);
    let capabilities = metadata
        .as_ref()
        .map(|metadata| metadata.capabilities.clone())
        .unwrap_or_default();
    let scaffold_version = metadata
        .as_ref()
        .and_then(|metadata| metadata.scaffold_version);

    check_workspace_manifest(repo, &mut checks);
    check_required_members(repo, &mut checks);
    check_rust_toolchain(repo, &mut checks);
    check_capability_paths(repo, &capabilities, &mut checks);
    check_xtask(repo, &capabilities, &mut checks);
    check_desktop_handshake(repo, &capabilities, &mut checks);
    check_simulation_fixtures(repo, &capabilities, &mut checks);
    check_gui_replay(repo, &capabilities, &mut checks);

    let status = aggregate_status(&checks);
    Ok(ScaffoldCheckResult {
        status,
        scaffold_version,
        capabilities,
        checks,
    })
}

fn read_metadata(repo: &Utf8Path, checks: &mut Vec<ScaffoldCheck>) -> Option<ParsedMetadata> {
    let path = repo.join(METADATA_PATH);
    let contents = match std::fs::read_to_string(&path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail(
                "metadata_present",
                "compass-scaffold.toml is missing.",
                METADATA_PATH,
            ));
            return None;
        }
        Err(error) => {
            checks.push(fail(
                "metadata_readable",
                format!("compass-scaffold.toml could not be read: {error}"),
                METADATA_PATH,
            ));
            return None;
        }
    };

    let parsed = parse_metadata(&contents);
    let mut valid = true;
    if parsed.schema_version != Some(1) {
        valid = false;
        checks.push(fail(
            "metadata_schema_version",
            "scaffold metadata must declare schema_version = 1.",
            METADATA_PATH,
        ));
    }
    if parsed.scaffold_version.is_none() {
        valid = false;
        checks.push(fail(
            "metadata_scaffold_version",
            "scaffold metadata must declare scaffold_version.",
            METADATA_PATH,
        ));
    }
    if parsed.profile.as_deref() != Some("rust-cargo") {
        valid = false;
        checks.push(fail(
            "metadata_profile",
            "scaffold metadata must declare profile = \"rust-cargo\".",
            METADATA_PATH,
        ));
    }
    if parsed.capabilities == ScaffoldCapabilities::default() {
        valid = false;
        checks.push(fail(
            "metadata_capabilities",
            "scaffold metadata must declare at least one capability.",
            METADATA_PATH,
        ));
    }
    if valid {
        checks.push(pass(
            "metadata_parse",
            "scaffold metadata parsed cleanly.",
            METADATA_PATH,
        ));
    }
    Some(parsed)
}

fn parse_metadata(contents: &str) -> ParsedMetadata {
    let mut section = String::new();
    let mut root = BTreeMap::new();
    let mut capabilities = BTreeMap::new();
    for raw_line in contents.lines() {
        let line = raw_line.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            section = line.trim_matches(['[', ']']).trim().to_owned();
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim().to_owned();
        let value = value.trim().trim_matches('"').to_owned();
        if section == "capabilities" {
            capabilities.insert(key, value);
        } else {
            root.insert(key, value);
        }
    }
    ParsedMetadata {
        schema_version: root
            .get("schema_version")
            .and_then(|value| value.parse::<u32>().ok()),
        scaffold_version: root
            .get("scaffold_version")
            .and_then(|value| value.parse::<u32>().ok()),
        profile: root.get("profile").cloned(),
        capabilities: ScaffoldCapabilities {
            xtask_verify: parse_bool(capabilities.get("xtask_verify")),
            visual_verify: parse_bool(capabilities.get("visual_verify")),
            schema_contracts: parse_bool(capabilities.get("schema_contracts")),
            desktop_handshake: parse_bool(capabilities.get("desktop_handshake")),
            simulation_fixtures: parse_bool(capabilities.get("simulation_fixtures")),
            gui_replay: parse_bool(capabilities.get("gui_replay")),
        },
    }
}

fn parse_bool(value: Option<&String>) -> bool {
    value
        .map(|value| value.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
}

fn check_workspace_manifest(repo: &Utf8Path, checks: &mut Vec<ScaffoldCheck>) {
    let path = repo.join("Cargo.toml");
    let contents = match std::fs::read_to_string(&path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail(
                "workspace_manifest",
                "root Cargo.toml is missing.",
                "Cargo.toml",
            ));
            return;
        }
        Err(error) => {
            checks.push(fail(
                "workspace_manifest",
                format!("root Cargo.toml could not be read: {error}"),
                "Cargo.toml",
            ));
            return;
        }
    };
    if contents.contains("[workspace]") {
        checks.push(pass(
            "workspace_manifest",
            "root Cargo.toml declares a workspace.",
            "Cargo.toml",
        ));
    } else {
        checks.push(fail(
            "workspace_manifest",
            "root Cargo.toml exists but does not declare [workspace].",
            "Cargo.toml",
        ));
    }
}

fn check_required_members(repo: &Utf8Path, checks: &mut Vec<ScaffoldCheck>) {
    for member in REQUIRED_MEMBERS {
        let manifest = format!("{member}/Cargo.toml");
        if repo.join(&manifest).is_file() {
            checks.push(pass(
                format!("member_{}", member.replace(['/', '-'], "_")),
                format!("required member {member} exists."),
                manifest,
            ));
        } else {
            checks.push(fail(
                format!("member_{}", member.replace(['/', '-'], "_")),
                format!("required member {member} is missing."),
                manifest,
            ));
        }
    }
}

fn check_rust_toolchain(repo: &Utf8Path, checks: &mut Vec<ScaffoldCheck>) {
    let path = "rust-toolchain.toml";
    let contents = match std::fs::read_to_string(repo.join(path)) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail(
                "rust_toolchain",
                "rust-toolchain.toml is missing.",
                path,
            ));
            return;
        }
        Err(error) => {
            checks.push(fail(
                "rust_toolchain",
                format!("rust-toolchain.toml could not be read: {error}"),
                path,
            ));
            return;
        }
    };
    for component in ["rustfmt", "clippy"] {
        if contents.contains(component) {
            checks.push(pass(
                format!("toolchain_{component}"),
                format!("rust-toolchain.toml includes {component}."),
                path,
            ));
        } else {
            checks.push(fail(
                format!("toolchain_{component}"),
                format!("rust-toolchain.toml is missing {component}."),
                path,
            ));
        }
    }
}

fn check_capability_paths(
    repo: &Utf8Path,
    capabilities: &ScaffoldCapabilities,
    checks: &mut Vec<ScaffoldCheck>,
) {
    if capabilities.schema_contracts {
        if repo.join("schemas").is_dir() {
            checks.push(pass(
                "schemas_directory",
                "schemas/ exists for schema contract capability.",
                "schemas",
            ));
        } else {
            checks.push(fail(
                "schemas_directory",
                "schema contract capability is advertised but schemas/ is missing.",
                "schemas",
            ));
        }
    }
    if capabilities.visual_verify {
        if repo.join("crates/app-desktop/Cargo.toml").is_file() {
            checks.push(pass(
                "visual_desktop_crate",
                "desktop crate exists for visual verification capability.",
                "crates/app-desktop/Cargo.toml",
            ));
        } else {
            checks.push(fail(
                "visual_desktop_crate",
                "visual verification capability is advertised but app-desktop is missing.",
                "crates/app-desktop/Cargo.toml",
            ));
        }
    }
}

fn check_xtask(
    repo: &Utf8Path,
    capabilities: &ScaffoldCapabilities,
    checks: &mut Vec<ScaffoldCheck>,
) {
    let path = "xtask/src/main.rs";
    let contents = match std::fs::read_to_string(repo.join(path)) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail("xtask_source", "xtask source is missing.", path));
            return;
        }
        Err(error) => {
            checks.push(fail(
                "xtask_source",
                format!("xtask source could not be read: {error}"),
                path,
            ));
            return;
        }
    };
    if capabilities.xtask_verify {
        check_source_contains(
            &contents,
            checks,
            "xtask_verify_command",
            "\"verify\"",
            path,
        );
    }
    if capabilities.visual_verify {
        check_source_contains(
            &contents,
            checks,
            "xtask_visual_verify_command",
            "\"visual-verify\"",
            path,
        );
    }
}

fn check_desktop_handshake(
    repo: &Utf8Path,
    capabilities: &ScaffoldCapabilities,
    checks: &mut Vec<ScaffoldCheck>,
) {
    if !capabilities.desktop_handshake && !capabilities.visual_verify {
        return;
    }
    let path = "crates/app-desktop/src/main.rs";
    let contents = match std::fs::read_to_string(repo.join(path)) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail("desktop_source", "desktop source is missing.", path));
            return;
        }
        Err(error) => {
            checks.push(fail(
                "desktop_source",
                format!("desktop source could not be read: {error}"),
                path,
            ));
            return;
        }
    };
    for flag in [
        "--visual-ready-file",
        "--visual-screenshot-file",
        "--visual-input-file",
        "--visual-input-ack-file",
    ] {
        check_source_contains(
            &contents,
            checks,
            format!(
                "desktop_handshake_{}",
                flag.trim_start_matches("--").replace('-', "_")
            ),
            flag,
            path,
        );
    }
}

fn check_simulation_fixtures(
    repo: &Utf8Path,
    capabilities: &ScaffoldCapabilities,
    checks: &mut Vec<ScaffoldCheck>,
) {
    if !capabilities.simulation_fixtures {
        return;
    }

    let core_path = "crates/app-core/src/lib.rs";
    let core = match std::fs::read_to_string(repo.join(core_path)) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail(
                "simulation_core_source",
                "simulation fixture capability is advertised but app-core source is missing.",
                core_path,
            ));
            return;
        }
        Err(error) => {
            checks.push(fail(
                "simulation_core_source",
                format!("app-core source could not be read: {error}"),
                core_path,
            ));
            return;
        }
    };
    for marker in ["SimulationInput", "SimulationSnapshot", "run_simulation"] {
        check_source_contains(
            &core,
            checks,
            format!("simulation_core_{}", marker.to_lowercase()),
            marker,
            core_path,
        );
    }

    let cli_path = "crates/app-cli/src/main.rs";
    let cli = match std::fs::read_to_string(repo.join(cli_path)) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail(
                "simulation_cli_source",
                "simulation fixture capability is advertised but app-cli source is missing.",
                cli_path,
            ));
            return;
        }
        Err(error) => {
            checks.push(fail(
                "simulation_cli_source",
                format!("app-cli source could not be read: {error}"),
                cli_path,
            ));
            return;
        }
    };
    for marker in ["simulate", "--input"] {
        check_source_contains(
            &cli,
            checks,
            format!("simulation_cli_{}", marker.trim_start_matches("--").replace('-', "_")),
            marker,
            cli_path,
        );
    }
}

fn check_gui_replay(
    repo: &Utf8Path,
    capabilities: &ScaffoldCapabilities,
    checks: &mut Vec<ScaffoldCheck>,
) {
    if !capabilities.gui_replay {
        return;
    }

    let core_path = "crates/app-core/src/lib.rs";
    let core = match std::fs::read_to_string(repo.join(core_path)) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail(
                "gui_replay_core_source",
                "GUI replay capability is advertised but app-core source is missing.",
                core_path,
            ));
            return;
        }
        Err(error) => {
            checks.push(fail(
                "gui_replay_core_source",
                format!("app-core source could not be read: {error}"),
                core_path,
            ));
            return;
        }
    };
    for marker in ["GuiReplayTrace", "GuiSemanticSnapshot", "run_gui_replay"] {
        check_source_contains(
            &core,
            checks,
            format!("gui_replay_core_{}", marker.to_lowercase()),
            marker,
            core_path,
        );
    }

    let cli_path = "crates/app-cli/src/main.rs";
    let cli = match std::fs::read_to_string(repo.join(cli_path)) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail(
                "gui_replay_cli_source",
                "GUI replay capability is advertised but app-cli source is missing.",
                cli_path,
            ));
            return;
        }
        Err(error) => {
            checks.push(fail(
                "gui_replay_cli_source",
                format!("app-cli source could not be read: {error}"),
                cli_path,
            ));
            return;
        }
    };
    for marker in ["gui-replay", "gui-replay-schema"] {
        check_source_contains(
            &cli,
            checks,
            format!("gui_replay_cli_{}", marker.replace('-', "_")),
            marker,
            cli_path,
        );
    }

    let desktop_path = "crates/app-desktop/src/main.rs";
    let desktop = match std::fs::read_to_string(repo.join(desktop_path)) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            checks.push(fail(
                "gui_replay_desktop_source",
                "GUI replay capability is advertised but app-desktop source is missing.",
                desktop_path,
            ));
            return;
        }
        Err(error) => {
            checks.push(fail(
                "gui_replay_desktop_source",
                format!("app-desktop source could not be read: {error}"),
                desktop_path,
            ));
            return;
        }
    };
    check_source_contains(
        &desktop,
        checks,
        "gui_replay_desktop_semantic_snapshot_flag",
        "--visual-semantic-snapshot-file",
        desktop_path,
    );
}

fn check_source_contains(
    contents: &str,
    checks: &mut Vec<ScaffoldCheck>,
    id: impl Into<String>,
    needle: &str,
    path: &str,
) {
    let id = id.into();
    if contents.contains(needle) {
        checks.push(pass(
            id,
            format!("{path} contains expected marker {needle}."),
            path,
        ));
    } else {
        checks.push(fail(
            id,
            format!("{path} is missing expected marker {needle}."),
            path,
        ));
    }
}

fn aggregate_status(checks: &[ScaffoldCheck]) -> CheckStatus {
    if checks.iter().any(|check| check.status == CheckStatus::Fail) {
        CheckStatus::Fail
    } else if checks.iter().any(|check| check.status == CheckStatus::Warn) {
        CheckStatus::Warn
    } else {
        CheckStatus::Pass
    }
}

fn pass(
    id: impl Into<String>,
    message: impl Into<String>,
    path: impl Into<String>,
) -> ScaffoldCheck {
    ScaffoldCheck {
        id: id.into(),
        status: CheckStatus::Pass,
        message: message.into(),
        path: Some(path.into()),
    }
}

fn fail(
    id: impl Into<String>,
    message: impl Into<String>,
    path: impl Into<String>,
) -> ScaffoldCheck {
    ScaffoldCheck {
        id: id.into(),
        status: CheckStatus::Fail,
        message: message.into(),
        path: Some(path.into()),
    }
}
