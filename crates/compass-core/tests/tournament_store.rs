use compass_core::tournament::read_model::ProductTournamentReadModelSummary;
use compass_core::tournament::store::TournamentWorkspaceStore;

#[test]
fn missing_state_returns_empty_tournament() {
    let root = temp_root("missing");
    let store = TournamentWorkspaceStore::new(&root);

    let state = store.read_state().unwrap();
    assert_eq!(state.schema_version, 1);
    assert!(state.contenders.is_empty());

    let summary = ProductTournamentReadModelSummary::from_state(&state);
    assert_eq!(summary.contender_count, 0);
    assert!(summary.validation_errors.is_empty());

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn validation_reports_unknown_round_contender() {
    let root = temp_root("invalid");
    let state_dir = root.join(".compass").join("tournament");
    std::fs::create_dir_all(&state_dir).unwrap();
    std::fs::write(
        state_dir.join("state.json"),
        r#"{
          "schemaVersion": 1,
          "contenders": [],
          "rounds": [
            {
              "id": "round-one",
              "ordinal": 1,
              "kind": "productPlans",
              "title": "Round one",
              "lifecycle": "active",
              "contenderIDs": ["missing-contender"]
            }
          ],
          "activeRoundID": "round-one",
          "decisionLog": []
        }"#,
    )
    .unwrap();

    let validation = TournamentWorkspaceStore::new(&root).validate().unwrap();
    assert!(!validation.ok);
    assert!(validation
        .errors
        .iter()
        .any(|error| error.contains("missing-contender")));

    let _ = std::fs::remove_dir_all(root);
}

fn temp_root(label: &str) -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!(
        "compass-core-tournament-{label}-{}-{}",
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
