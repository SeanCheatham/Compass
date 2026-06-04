use assert_cmd::Command;
use serde_json::Value;

#[test]
fn workspace_outline_lists_members_and_edges() {
    let fixture = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/blessed-workspace"
    );
    let output = Command::cargo_bin("compass-engine")
        .expect("binary")
        .args(["workspace-outline", "--repo", fixture, "--format", "json"])
        .output()
        .expect("run engine");
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let json: Value = serde_json::from_slice(&output.stdout).expect("json");
    assert_eq!(json["ok"], true);
    let members = json["data"]["members"].as_array().expect("members");
    let names = members
        .iter()
        .map(|member| member["name"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(names, ["app-cli", "app-core", "app-desktop", "xtask"]);
    let edges = json["data"]["edges"].as_array().expect("edges");
    assert!(edges.iter().any(|edge| {
        edge["from"] == "app-cli" && edge["to"] == "app-core" && edge["dev"] == false
    }));
    assert!(edges.iter().any(|edge| {
        edge["from"] == "app-desktop" && edge["to"] == "app-core"
    }));
}
