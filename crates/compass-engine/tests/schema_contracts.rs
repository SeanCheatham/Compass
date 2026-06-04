use assert_cmd::Command;
use serde_json::Value;

#[test]
fn schema_contracts_links_schema_to_rust_type() {
    let fixture = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/blessed-workspace"
    );
    let output = Command::cargo_bin("compass-engine")
        .expect("binary")
        .args(["schema-contracts", "--repo", fixture, "--format", "json"])
        .output()
        .expect("run engine");
    assert!(output.status.success());
    let json: Value = serde_json::from_slice(&output.stdout).expect("json");
    assert_eq!(json["audit"]["argv"], Value::Null);
    assert!(json["audit"]["duration_ms"].as_u64().is_some());
    let contracts = json["data"]["contracts"].as_array().expect("contracts");
    assert!(contracts.iter().any(|contract| {
        contract["schema_path"] == "schemas/demo-state.schema.json"
            && contract["rust_type"] == "DemoState"
            && contract["confidence"] == "high"
    }));
}
