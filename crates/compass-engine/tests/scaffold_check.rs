use assert_cmd::Command;
use serde_json::Value;
use std::path::Path;

#[test]
fn scaffold_check_passes_for_blessed_shape() {
    let temp = tempfile::tempdir().expect("tempdir");
    write_blessed_workspace(temp.path());

    let json = run_scaffold_check(temp.path());

    assert_eq!(json["ok"], true);
    assert_eq!(json["data"]["status"], "pass");
    assert_eq!(json["data"]["scaffold_version"], 1);
    assert_eq!(json["data"]["capabilities"]["xtask_verify"], true);
    assert_eq!(json["data"]["capabilities"]["simulation_fixtures"], true);
    assert_eq!(json["data"]["capabilities"]["gui_replay"], true);
}

#[test]
fn scaffold_check_reports_missing_member_with_stable_id() {
    let temp = tempfile::tempdir().expect("tempdir");
    write_blessed_workspace(temp.path());
    std::fs::remove_dir_all(temp.path().join("crates/app-cli")).expect("remove app-cli");

    let json = run_scaffold_check(temp.path());
    let checks = json["data"]["checks"].as_array().expect("checks");

    assert_eq!(json["ok"], true);
    assert_eq!(json["data"]["status"], "fail");
    assert!(checks
        .iter()
        .any(|check| { check["id"] == "member_crates_app_cli" && check["status"] == "fail" }));
    assert!(json["repair_hints"]
        .as_array()
        .expect("repair hints")
        .iter()
        .any(|hint| { hint["id"] == "generated-scaffold-missing-member" }));
}

#[test]
fn scaffold_check_returns_structured_failure_for_non_workspace() {
    let temp = tempfile::tempdir().expect("tempdir");
    std::fs::write(
        temp.path().join("Cargo.toml"),
        "[package]\nname = \"not-workspace\"\n",
    )
    .expect("write manifest");

    let json = run_scaffold_check(temp.path());
    let checks = json["data"]["checks"].as_array().expect("checks");

    assert_eq!(json["ok"], true);
    assert_eq!(json["data"]["status"], "fail");
    assert!(checks
        .iter()
        .any(|check| { check["id"] == "metadata_present" && check["status"] == "fail" }));
    assert!(checks
        .iter()
        .any(|check| { check["id"] == "workspace_manifest" && check["status"] == "fail" }));
}

#[test]
fn scaffold_check_reports_missing_simulation_fixture_markers() {
    let temp = tempfile::tempdir().expect("tempdir");
    write_blessed_workspace(temp.path());
    write(
        temp.path(),
        "crates/app-cli/src/main.rs",
        r#"
fn main() {
    println!("status only");
}
"#,
    );

    let json = run_scaffold_check(temp.path());
    let checks = json["data"]["checks"].as_array().expect("checks");

    assert_eq!(json["ok"], true);
    assert_eq!(json["data"]["status"], "fail");
    assert!(checks
        .iter()
        .any(|check| { check["id"] == "simulation_cli_simulate" && check["status"] == "fail" }));
    assert!(json["repair_hints"]
        .as_array()
        .expect("repair hints")
        .iter()
        .any(|hint| { hint["id"] == "generated-scaffold-missing-simulation-fixture" }));
}

#[test]
fn scaffold_check_reports_missing_gui_replay_markers() {
    let temp = tempfile::tempdir().expect("tempdir");
    write_blessed_workspace(temp.path());
    write(
        temp.path(),
        "crates/app-desktop/src/main.rs",
        r#"
fn main() {
    let _ = "--visual-ready-file";
    let _ = "--visual-screenshot-file";
    let _ = "--visual-input-file";
    let _ = "--visual-input-ack-file";
}
"#,
    );

    let json = run_scaffold_check(temp.path());
    let checks = json["data"]["checks"].as_array().expect("checks");

    assert_eq!(json["ok"], true);
    assert_eq!(json["data"]["status"], "fail");
    assert!(checks.iter().any(|check| {
        check["id"] == "gui_replay_desktop_semantic_snapshot_flag"
            && check["status"] == "fail"
    }));
    assert!(json["repair_hints"]
        .as_array()
        .expect("repair hints")
        .iter()
        .any(|hint| { hint["id"] == "generated-scaffold-missing-gui-replay" }));
}

fn run_scaffold_check(path: &Path) -> Value {
    let output = Command::cargo_bin("compass-engine")
        .expect("binary")
        .args(["scaffold-check", "--repo"])
        .arg(path)
        .args(["--format", "json"])
        .output()
        .expect("run engine");
    assert!(
        output.status.success(),
        "stderr: {}\nstdout: {}",
        String::from_utf8_lossy(&output.stderr),
        String::from_utf8_lossy(&output.stdout)
    );
    serde_json::from_slice(&output.stdout).expect("json")
}

fn write_blessed_workspace(root: &Path) {
    write(
        root,
        "compass-scaffold.toml",
        r#"
schema_version = 1
scaffold_version = 1
profile = "rust-cargo"

[capabilities]
xtask_verify = true
visual_verify = true
schema_contracts = true
desktop_handshake = true
simulation_fixtures = true
gui_replay = true
"#,
    );
    write(
        root,
        "Cargo.toml",
        r#"
[workspace]
resolver = "2"
members = [
  "crates/app-core",
  "crates/app-cli",
  "crates/app-desktop",
  "xtask",
]
"#,
    );
    write(
        root,
        "rust-toolchain.toml",
        r#"
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
"#,
    );
    for member in [
        "crates/app-core",
        "crates/app-cli",
        "crates/app-desktop",
        "xtask",
    ] {
        write(
            root,
            &format!("{member}/Cargo.toml"),
            "[package]\nname = \"fixture\"\n",
        );
    }
    write(root, "schemas/demo-state.schema.json", "{}");
    write(root, "schemas/simulation-input.schema.json", "{}");
    write(root, "schemas/gui-replay-trace.schema.json", "{}");
    write(
        root,
        "xtask/src/main.rs",
        r#"
fn main() {
    match "verify" {
        "verify" => {}
        "visual-verify" => {}
        _ => {}
    }
}
"#,
    );
    write(
        root,
        "crates/app-core/src/lib.rs",
        r#"
pub struct SimulationInput;
pub struct SimulationSnapshot;
pub struct GuiReplayTrace;
pub struct GuiSemanticSnapshot;
pub fn run_simulation(_: SimulationInput) -> SimulationSnapshot {
    SimulationSnapshot
}
pub fn run_gui_replay(_: GuiReplayTrace) -> GuiSemanticSnapshot {
    GuiSemanticSnapshot
}
"#,
    );
    write(
        root,
        "crates/app-cli/src/main.rs",
        r#"
fn main() {
    let _ = "simulate";
    let _ = "--input";
    let _ = "gui-replay";
    let _ = "gui-replay-schema";
}
"#,
    );
    write(
        root,
        "crates/app-desktop/src/main.rs",
        r#"
fn main() {
    let _ = "--visual-ready-file";
    let _ = "--visual-screenshot-file";
    let _ = "--visual-input-file";
    let _ = "--visual-input-ack-file";
    let _ = "--visual-semantic-snapshot-file";
}
"#,
    );
}

fn write(root: &Path, relative: &str, contents: &str) {
    let path = root.join(relative);
    std::fs::create_dir_all(path.parent().expect("parent")).expect("create parent");
    std::fs::write(path, contents).expect("write fixture");
}
