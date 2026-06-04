use assert_cmd::Command;
use serde_json::Value;

#[test]
fn cargo_check_reports_rustc_diagnostic() {
    let json = run_engine("cargo-check", "broken-compile");
    assert_eq!(json["ok"], true);
    assert_eq!(
        json["audit"]["argv"],
        serde_json::json!(["cargo", "check", "--workspace", "--message-format=json"])
    );
    assert!(json["audit"]["duration_ms"].as_u64().is_some());
    assert!(json["audit"]["toolchain"]["cargo"]
        .as_str()
        .unwrap_or_default()
        .starts_with("cargo "));
    assert_eq!(json["data"]["exit_code"], 101);
    let diagnostics = json["data"]["diagnostics"].as_array().expect("diagnostics");
    assert!(diagnostics.iter().any(|diagnostic| {
        diagnostic["code"] == "E0425"
            && diagnostic["file"] == "src/lib.rs"
            && diagnostic["line"] == 2
    }));
}

#[test]
fn clippy_lint_reports_lint_name() {
    let json = run_engine("clippy-lint", "clippy-warnings");
    assert_eq!(json["ok"], true);
    assert_eq!(
        json["audit"]["argv"],
        serde_json::json!([
            "cargo",
            "clippy",
            "--workspace",
            "--all-targets",
            "--message-format=json",
            "--",
            "-D",
            "warnings"
        ])
    );
    let diagnostics = json["data"]["diagnostics"].as_array().expect("diagnostics");
    assert!(diagnostics.iter().any(|diagnostic| {
        diagnostic["code"]
            .as_str()
            .unwrap_or_default()
            .contains("clippy::needless_bool")
    }));
}

#[test]
fn cargo_test_reports_pass_counts() {
    let json = run_engine("cargo-test", "passing-tests");
    assert_eq!(json["ok"], true);
    assert_eq!(
        json["audit"]["argv"],
        serde_json::json!(["cargo", "test", "--workspace"])
    );
    assert_eq!(json["data"]["exit_code"], 0);
    assert_eq!(json["data"]["passed"], 1);
    assert_eq!(json["data"]["failed"], 0);
}

fn run_engine(command_name: &str, fixture_name: &str) -> Value {
    let fixture = format!(
        "{}/tests/fixtures/{}",
        env!("CARGO_MANIFEST_DIR"),
        fixture_name
    );
    let output = Command::cargo_bin("compass-engine")
        .expect("binary")
        .args([command_name, "--repo", &fixture, "--format", "json"])
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
