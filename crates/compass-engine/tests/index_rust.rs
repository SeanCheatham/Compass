use assert_cmd::Command;
use serde_json::Value;

#[test]
fn index_rust_resolves_cross_crate_imports_and_impls() {
    let fixture = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/blessed-workspace"
    );
    let output = Command::cargo_bin("compass-engine")
        .expect("binary")
        .args(["index-rust", "--repo", fixture, "--format", "json"])
        .output()
        .expect("run engine");
    assert!(
        output.status.success(),
        "stderr: {}\nstdout: {}",
        String::from_utf8_lossy(&output.stderr),
        String::from_utf8_lossy(&output.stdout)
    );
    let json: Value = serde_json::from_slice(&output.stdout).expect("json");
    assert_eq!(json["ok"], true);
    let core = &json["data"]["module_index"]["files"]["crates/app-core/src/lib.rs"];
    let incoming = core["incoming"].as_array().expect("incoming");
    assert!(incoming.iter().any(|edge| {
        edge["from_file"] == "crates/app-cli/src/main.rs"
    }));
    assert!(incoming.iter().any(|edge| {
        edge["from_file"] == "crates/app-desktop/src/main.rs"
    }));
    let impls = json["data"]["trait_index"]["impls"].as_array().expect("impls");
    assert!(impls.iter().any(|item| {
        item["trait_name"] == "Display" && item["type_name"] == "DemoState"
    }));
}
