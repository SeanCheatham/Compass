use assert_cmd::Command;
use predicates::prelude::*;

#[test]
fn ping_returns_json_envelope() {
    let temp = tempfile::tempdir().expect("tempdir");
    std::fs::write(
        temp.path().join("Cargo.toml"),
        "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .expect("write manifest");

    let mut command = Command::cargo_bin("compass-engine").expect("binary");
    command
        .arg("ping")
        .arg("--repo")
        .arg(temp.path())
        .arg("--format")
        .arg("json")
        .assert()
        .success()
        .stdout(predicate::str::contains("\"schema_version\": 1"))
        .stdout(predicate::str::contains("\"command\": \"ping\""))
        .stdout(predicate::str::contains("\"ok\": true"));
}
