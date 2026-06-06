import Foundation
import Testing

@testable import Compass

struct RustProjectScaffoldTests {
  @Test func scaffoldUsesBlessedCargoWorkspaceShape() throws {
    let files = RustProjectScaffold.files()
    let paths = Set(files.map(\.path))

    try #require(paths.contains("Cargo.toml"))
    try #require(paths.contains("compass-scaffold.toml"))
    try #require(paths.contains("rust-toolchain.toml"))
    try #require(paths.contains("crates/app-core/src/lib.rs"))
    try #require(paths.contains("crates/app-cli/src/main.rs"))
    try #require(paths.contains("crates/app-desktop/src/main.rs"))
    try #require(paths.contains("xtask/src/main.rs"))
    try #require(paths.contains("schemas/demo-state.schema.json"))
    try #require(paths.contains("schemas/simulation-input.schema.json"))
    try #require(paths.contains("schemas/gui-replay-trace.schema.json"))
    try #require(paths.contains("schemas/product-tournament-experience-input.schema.json"))
    try #require(paths.contains("schemas/product-tournament-experience-trace.schema.json"))
    try #require(!paths.contains("Package.swift"))
    try #require(!paths.contains("package.json"))
  }

  @Test func scaffoldDeclaresCompassMetadataAndCapabilities() throws {
    let metadata = try #require(
      RustProjectScaffold.files().first { $0.path == "compass-scaffold.toml" }?.contents)

    try #require(metadata.contains("schema_version = 1"))
    try #require(metadata.contains("scaffold_version = 1"))
    try #require(metadata.contains(#"profile = "rust-cargo""#))
    try #require(metadata.contains("xtask_verify = true"))
    try #require(metadata.contains("visual_verify = true"))
    try #require(metadata.contains("schema_contracts = true"))
    try #require(metadata.contains("desktop_handshake = true"))
    try #require(metadata.contains("simulation_fixtures = true"))
    try #require(metadata.contains("gui_replay = true"))
    try #require(metadata.contains("product_tournament_experience = true"))
  }

  @Test func scaffoldDocumentsStandardRustCommandsAndDesktopStack() throws {
    let readme = try #require(
      RustProjectScaffold.files().first { $0.path == "README.md" }?.contents)
    let removedEngineParityCommand = "engine" + "-parity-check"

    try #require(readme.contains("Compass itself remains a native Swift/macOS app"))
    try #require(readme.contains("generated output lives here as Rust"))
    try #require(readme.contains("mirror Compass Product Tournament engine behavior"))
    try #require(readme.contains("eframe"))
    try #require(readme.contains("egui"))
    try #require(readme.contains("Deterministic Simulation Contract"))
    try #require(readme.contains("run_simulation(SimulationInput) -> SimulationSnapshot"))
    try #require(readme.contains("app-cli simulate --input"))
    try #require(readme.contains("Murphy scenarios"))
    try #require(readme.contains("Deterministic GUI Replay Contract"))
    try #require(readme.contains("run_gui_replay(GuiReplayTrace) -> GuiSemanticSnapshot"))
    try #require(readme.contains("app-cli gui-replay --input"))
    try #require(readme.contains("Deterministic Product Tournament Experience Contract"))
    try #require(readme.contains("run_product_tournament_experience(ProductTournamentExperienceInput) ->"))
    try #require(readme.contains("app-cli product-tournament-experience --input"))
    try #require(readme.contains("Product Tournament evidence is product pressure"))
    try #require(readme.contains("Manual product tournament simulation checklist"))
    try #require(readme.contains("allowedNextActions"))
    try #require(readme.contains("avoid optimizing for praise"))
    try #require(
      readme.contains(RustVerifyCommands.cargo(RustVerifyCommands.productTournamentSmoke)))
    try #require(readme.contains(RustVerifyCommands.cargo(RustVerifyCommands.fmt)))
    try #require(readme.contains(RustVerifyCommands.cargo(RustVerifyCommands.clippy)))
    try #require(readme.contains(RustVerifyCommands.cargo(RustVerifyCommands.test)))
    try #require(readme.contains(RustVerifyCommands.cargo(RustVerifyCommands.coverage)))
    try #require(readme.contains(RustVerifyCommands.cargo(RustVerifyCommands.build)))
    try #require(readme.contains(RustVerifyCommands.cargo(RustVerifyCommands.fastVerify)))
    try #require(readme.contains(RustProjectScaffold.productTournamentSmokeCommand))
    try #require(readme.contains(RustProjectScaffold.productTournamentSmokeWithScreenshotCommand))
    try #require(readme.contains(RustProjectScaffold.visualVerifyCommand))
    try #require(!readme.contains(removedEngineParityCommand))
    try #require(!readme.contains("compatibility alias"))
    try #require(readme.contains("launch it in the guest"))
    try #require(readme.contains("platform-neutral visual input request"))
  }

  @Test func appCoreTemplateExposesDeterministicSimulationFixture() throws {
    let core = try #require(
      RustProjectScaffold.files().first { $0.path == "crates/app-core/src/lib.rs" }?.contents)
    let cli = try #require(
      RustProjectScaffold.files().first { $0.path == "crates/app-cli/src/main.rs" }?.contents)
    let tests = try #require(
      RustProjectScaffold.files().first { $0.path == "crates/app-core/tests/state_tests.rs" }?
        .contents)

    try #require(core.contains("pub struct SimulationInput"))
    try #require(core.contains("pub struct SimulationSnapshot"))
    try #require(core.contains("pub fn run_simulation"))
    try #require(core.contains("event_log: Vec<String>"))
    try #require(core.contains("pub struct GuiReplayTrace"))
    try #require(core.contains("pub struct GuiSemanticSnapshot"))
    try #require(core.contains("pub fn run_gui_replay"))
    try #require(core.contains("pub fn gui_semantic_snapshot"))
    try #require(core.contains("pub struct ProductTournamentExperienceInput"))
    try #require(core.contains("pub struct ProductTournamentPain"))
    try #require(core.contains("pub struct ProductTournamentSolution"))
    try #require(core.contains("pub struct ProductTournamentExperiment"))
    try #require(core.contains("pub struct ProductTournamentScenario"))
    try #require(core.contains("pub struct ProductTournamentCurrentWorkflow"))
    try #require(core.contains("pub struct ProductTournamentAlternative"))
    try #require(core.contains("pub struct ProductTournamentDecisionIntent"))
    try #require(core.contains("pub decision_intent: Option<ProductTournamentDecisionIntent>"))
    try #require(tests.contains("ProductTournamentDecisionIntent"))
    try #require(core.contains("Decision intent:"))
    try #require(core.contains("decision intent: {decision_intent}"))
    try #require(core.contains("pub struct ProductTournamentExperienceState"))
    try #require(core.contains("pub struct ProductTournamentExperienceAction"))
    try #require(core.contains("pub struct ProductTournamentExperienceAllowedAction"))
    try #require(core.contains("pub struct ProductTournamentExperienceTrace"))
    try #require(core.contains("pub struct PainReliefSignals"))
    try #require(core.contains("pub fn run_product_tournament_experience"))
    try #require(cli.contains(#"Some("simulate")"#))
    try #require(cli.contains(#"Some("gui-replay")"#))
    try #require(cli.contains(#"Some("product-tournament-experience")"#))
    try #require(cli.contains(#"Some("product-tournament-experience-schema")"#))
    try #require(!cli.contains(#"Some("experience")"#))
    try #require(!cli.contains(#"Some("experience-schema")"#))
    try #require(cli.contains("--input"))
    try #require(cli.contains("serde_json::to_string_pretty(&run_simulation(input))"))
    try #require(cli.contains("serde_json::to_string_pretty(&run_gui_replay(trace))"))
    try #require(
      cli.contains("serde_json::to_string_pretty(&run_product_tournament_experience(input))"))
    try #require(tests.contains("simulation_fixture_is_a_pure_transition"))
    try #require(tests.contains("gui_replay_fixture_emits_stable_semantic_snapshot"))
    try #require(
      tests.contains("product_tournament_experience_fixture_replays_allowed_actions_deterministically"))
  }

  @Test func desktopTemplateHasStableVisualVerificationLabels() throws {
    let desktop = try #require(
      RustProjectScaffold.files().first { $0.path == "crates/app-desktop/src/main.rs" }?.contents)

    try #require(desktop.contains("Compass Rust Desktop"))
    try #require(desktop.contains("Visual verification target"))
    try #require(desktop.contains("Project health"))
    try #require(desktop.contains("--visual-ready-file"))
    try #require(desktop.contains("--visual-pid-file"))
    try #require(desktop.contains("--visual-screenshot-file"))
    try #require(desktop.contains("--visual-input-file"))
    try #require(desktop.contains("--visual-input-ack-file"))
    try #require(desktop.contains("--visual-semantic-snapshot-file"))
    try #require(desktop.contains("write_semantic_snapshot_file"))
    try #require(desktop.contains("gui_semantic_snapshot"))
    try #require(desktop.contains("input: {}"))
    try #require(desktop.contains("acknowledged"))
    try #require(desktop.contains("write_ready_file"))
    try #require(desktop.contains("write_visual_input_ack"))
    try #require(desktop.contains("write_screenshot_file"))
    try #require(desktop.contains("egui::ViewportCommand::Screenshot"))
    try #require(desktop.contains("std::process::id()"))
  }

  @Test func desktopTemplateEscapesWindowTitleForRustSource() throws {
    let desktop = try #require(
      RustProjectScaffold.files(
        options: RustProjectScaffold.Options(
          projectName: "Demo",
          windowTitle: #"Quote " and slash \"#
        )
      ).first { $0.path == "crates/app-desktop/src/main.rs" }?.contents)

    try #require(desktop.contains(#"window_title: "Quote \" and slash \\".to_owned()"#))
  }

  @Test func xtaskImplementsLevelTwoVisualVerificationSteps() throws {
    let xtask = try #require(
      RustProjectScaffold.files().first { $0.path == "xtask/src/main.rs" }?.contents)
    let removedLegacySmokeCommand = "factory" + "-smoke"
    let removedEngineParityCommand = "engine" + "-parity-check"
    let removedLegacySmokeFunction = "fn " + "factory" + "_smoke"

    try #require(xtask.contains("cargo"))
    try #require(xtask.contains("build"))
    try #require(xtask.contains("product-tournament-smoke"))
    try #require(
      xtask.contains(
        #""product-tournament-smoke" => {"#
      ))
    try #require(
      xtask.contains(#"product_tournament_smoke(args.iter().any(|arg| arg == "--emit-base64"))"#))
    try #require(xtask.contains("fn product_tournament_smoke(emit_base64: bool) -> Result<()>"))
    try #require(xtask.contains("fn product_tournament_trace_check() -> Result<()>"))
    try #require(xtask.contains("allowedNextActions"))
    try #require(xtask.contains("product tournament trace changed across identical invocations"))
    try #require(xtask.contains("painReliefSignals"))
    try #require(xtask.contains("willingnessToPayScore"))
    try #require(xtask.contains("sponsorshipIntent"))
    try #require(!xtask.contains(removedEngineParityCommand))
    try #require(!xtask.contains(removedLegacySmokeCommand))
    try #require(!xtask.contains(removedLegacySmokeFunction))
    try #require(xtask.contains("fn run_clippy() -> Result<()>"))
    try #require(xtask.contains(#""clippy" => run_clippy()"#))
    try #require(xtask.contains("run_clippy()?"))
    try #require(xtask.contains("product_tournament_trace_check()?"))
    try #require(xtask.contains("visual_verify(emit_base64)?"))
    try #require(
      xtask.contains("run(\"cargo\", &[\"test\", \"--workspace\", \"--all-features\"])?"))
    try #require(
      xtask.contains("\"coverage\" => run(\"cargo\", &[\"llvm-cov\", \"--summary-only\"])"))
    try #require(xtask.contains("run(\"cargo\", &[\"llvm-cov\", \"--summary-only\"])?"))
    try #require(xtask.contains("spawn_desktop"))
    try #require(xtask.contains("wait_for_file"))
    try #require(xtask.contains("--visual-screenshot-file"))
    try #require(xtask.contains("--visual-input-file"))
    try #require(xtask.contains("--visual-input-ack-file"))
    try #require(xtask.contains("--visual-semantic-snapshot-file"))
    try #require(xtask.contains("semantic GUI snapshot"))
    try #require(xtask.contains("COMPASS_VISUAL_SEMANTIC_SNAPSHOT_PATH"))
    try #require(!xtask.contains("launchctl"))
    try #require(!xtask.contains("screencapture"))
    try #require(!xtask.contains("osascript"))
    try #require(xtask.contains("send_basic_input"))
    try #require(xtask.contains("basic input acknowledgement"))
    try #require(xtask.contains("log_tail"))
    try #require(xtask.contains("COMPASS_VISUAL_SCREENSHOT_PATH"))
    try #require(xtask.contains("terminate"))
    try #require(xtask.contains("-TERM"))
    try #require(xtask.contains(RustDesktopVisualVerification.screenshotBeginMarker))
    try #require(xtask.contains(RustDesktopVisualVerification.screenshotEndMarker))
  }

  @Test func generatedXtaskVerifyTierDoesNotLaunchDesktop() throws {
    let xtask = try #require(
      RustProjectScaffold.files().first { $0.path == "xtask/src/main.rs" }?.contents)
    let verifyStart = try #require(xtask.range(of: "fn verify_all()"))
    let smokeStart = try #require(xtask.range(of: "fn product_tournament_smoke"))
    let verifyBody = String(xtask[verifyStart.lowerBound..<smokeStart.lowerBound])

    try #require(!verifyBody.contains("visual_verify"))
    try #require(!verifyBody.contains("app-desktop"))
  }

  @Test func writeCreatesDetectableBlessedDesktopWorkspace() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }

    try RustProjectScaffold.write(
      to: root,
      options: RustProjectScaffold.Options(projectName: "Demo")
    )

    try #require(RustProjectScaffold.isBlessedDesktopWorkspace(at: root))
    try #require(FileManager.default.fileExists(atPath: root.appending(path: ".gitignore").path))
  }

  @MainActor
  @Test func generatedRustProjectInitializerStampsRustForgeProfile() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }

    try await AppModel.initializeGeneratedRustProject(at: root)

    let workspace = CompassWorkspace(repoURL: root)
    let record = try #require(ForgeProfileService.readRecord(from: workspace))
    try #require(record.profile == .rustCargo)
    try #require(record.version == ForgeProfileRecord.currentVersion)
    try #require(RustProjectScaffold.isBlessedDesktopWorkspace(at: root))

    let status = try await ProcessRunner.runEnv(
      "git",
      ["status", "--porcelain"],
      workingDirectory: root
    )
    try #require(status.exitCode == 0)
    try #require(status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

    let log = try await ProcessRunner.runEnv(
      "git",
      ["log", "--format=%s", "-1"],
      workingDirectory: root
    )
    try #require(log.exitCode == 0)
    try #require(
      log.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Create Rust project scaffold")
  }

  @Test func generatedRustScaffoldCargoSmokeWhenRequested() async throws {
    guard ProcessInfo.processInfo.environment["COMPASS_RUN_GENERATED_RUST_SMOKE"] == "1" else {
      return
    }

    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try RustProjectScaffold.write(
      to: root,
      options: RustProjectScaffold.Options(projectName: "Compass Cargo Smoke")
    )

    let hasCoverageTooling = await cargoSubcommandAvailable("llvm-cov")
    if hasCoverageTooling {
      try await requireCommand(["run", "-p", "xtask", "--", "verify"], in: root)
    } else {
      print("Skipping generated `xtask verify`: cargo llvm-cov is not installed.")
      try await requireCommand(["fmt", "--all", "--check"], in: root)
      try await requireCommand(["test", "--workspace", "--all-features"], in: root)
      try await requireCommand(["build", "--workspace"], in: root)
    }
    if hasCoverageTooling {
      try await requireCommand(["run", "-p", "xtask", "--", "product-tournament-smoke"], in: root)
    } else {
      print("Skipping generated `product-tournament-smoke`: cargo llvm-cov is not installed.")
      try await requireCommand(["run", "-p", "app-cli", "--", "product-tournament-experience"], in: root)
    }
    try await requireCommand(["build", "-p", RustProjectScaffold.desktopPackage], in: root)
  }

  private func cargoSubcommandAvailable(_ name: String) async -> Bool {
    guard
      let result = try? await ProcessRunner.runEnv(
        "cargo",
        ["--list"],
        timeout: 30
      ),
      result.exitCode == 0
    else {
      return false
    }
    return result.stdout
      .split(whereSeparator: \.isNewline)
      .contains { line in
        line.trimmingCharacters(in: .whitespaces).hasPrefix("\(name) ")
          || line.trimmingCharacters(in: .whitespaces) == name
      }
  }

  private func requireCommand(_ arguments: [String], in root: URL) async throws {
    let result = try await ProcessRunner.runEnv(
      "cargo",
      arguments,
      workingDirectory: root,
      timeout: 20 * 60
    )
    try #require(
      result.exitCode == 0,
      "cargo \(arguments.joined(separator: " ")) failed:\n\(result.stdout)\n\(result.stderr)"
    )
  }
}
