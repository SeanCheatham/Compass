use compass_core::agent::tools;

#[test]
fn host_tools_read_write_glob_grep_and_bash() {
    let root = temp_root();
    tools::write_file(&root, "src/lib.rs", "pub fn marker() {}\n").unwrap();

    assert_eq!(
        tools::read_file(&root, "src/lib.rs").unwrap(),
        "pub fn marker() {}\n"
    );
    assert_eq!(
        tools::glob_files(&root, "src/*.rs").unwrap(),
        vec!["src/lib.rs"]
    );
    assert_eq!(
        tools::grep(&root, "marker").unwrap(),
        vec!["src/lib.rs:1:pub fn marker() {}"]
    );

    let output = tools::bash(&root, "printf ok").unwrap();
    assert!(output.ok);
    assert_eq!(output.stdout, "ok");

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn host_tools_reject_parent_directory_escape() {
    let root = temp_root();
    let error = tools::read_file(&root, "../outside").unwrap_err();
    assert!(error.to_string().contains("workspace-relative"));
    let _ = std::fs::remove_dir_all(root);
}

fn temp_root() -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!(
        "compass-core-agent-tools-{}-{}",
        std::process::id(),
        unique_suffix()
    ));
    std::fs::create_dir_all(&root).unwrap();
    root
}

fn unique_suffix() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}
