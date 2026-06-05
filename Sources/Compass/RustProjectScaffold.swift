import Foundation

struct RustProjectScaffold: Equatable, Sendable {
  struct Options: Equatable, Sendable {
    var projectName: String
    var windowTitle: String

    init(projectName: String = "Compass Rust App", windowTitle: String = "Compass Rust Desktop") {
      self.projectName = projectName
      self.windowTitle = windowTitle
    }
  }

  struct ScaffoldFile: Equatable, Sendable {
    var path: String
    var contents: String
  }

  static let desktopPackage = "app-desktop"
  static let desktopBinary = "app-desktop"
  static let visualVerifyCommand = RustVerifyCommands.cargo(RustVerifyCommands.visualVerify)
  static let factorySmokeCommand = RustVerifyCommands.cargo(RustVerifyCommands.factorySmoke)
  static let factorySmokeWithScreenshotCommand = RustVerifyCommands.cargo(
    RustVerifyCommands.factorySmokeWithScreenshot)

  static func write(to rootURL: URL, options: Options = Options()) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
    for file in files(options: options) {
      let url = rootURL.appending(path: file.path)
      try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try file.contents.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  static func files(options: Options = Options()) -> [ScaffoldFile] {
    let projectName = boundedLine(options.projectName, fallback: "Compass Rust App")
    let windowTitle = boundedLine(options.windowTitle, fallback: "Compass Rust Desktop")
    return [
      ScaffoldFile(path: ".gitignore", contents: gitignore()),
      ScaffoldFile(path: "compass-scaffold.toml", contents: scaffoldMetadata()),
      ScaffoldFile(path: "Cargo.toml", contents: workspaceManifest()),
      ScaffoldFile(path: "rust-toolchain.toml", contents: rustToolchain()),
      ScaffoldFile(path: "README.md", contents: readme(projectName: projectName)),
      ScaffoldFile(path: "schemas/demo-state.schema.json", contents: demoStateSchema()),
      ScaffoldFile(path: "schemas/simulation-input.schema.json", contents: simulationInputSchema()),
      ScaffoldFile(path: "schemas/gui-replay-trace.schema.json", contents: guiReplayTraceSchema()),
      ScaffoldFile(
        path: "schemas/productization-experience-input.schema.json",
        contents: productizationExperienceInputSchema()
      ),
      ScaffoldFile(
        path: "schemas/productization-experience-trace.schema.json",
        contents: productizationExperienceTraceSchema()
      ),
      ScaffoldFile(path: "crates/app-core/Cargo.toml", contents: appCoreManifest()),
      ScaffoldFile(path: "crates/app-core/src/lib.rs", contents: appCoreLib()),
      ScaffoldFile(path: "crates/app-core/tests/state_tests.rs", contents: appCoreTests()),
      ScaffoldFile(path: "crates/app-cli/Cargo.toml", contents: appCLIManifest()),
      ScaffoldFile(path: "crates/app-cli/src/main.rs", contents: appCLIMain()),
      ScaffoldFile(path: "crates/app-desktop/Cargo.toml", contents: appDesktopManifest()),
      ScaffoldFile(
        path: "crates/app-desktop/src/main.rs",
        contents: appDesktopMain(windowTitle: windowTitle)
      ),
      ScaffoldFile(path: "xtask/Cargo.toml", contents: xtaskManifest()),
      ScaffoldFile(path: "xtask/src/main.rs", contents: xtaskMain()),
    ]
  }

  static func isBlessedDesktopWorkspace(at rootURL: URL) -> Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: rootURL.appending(path: "Cargo.toml").path)
      && fm.fileExists(atPath: rootURL.appending(path: "crates/app-desktop/Cargo.toml").path)
      && fm.fileExists(atPath: rootURL.appending(path: "xtask/Cargo.toml").path)
  }

  private static func boundedLine(_ value: String, fallback: String) -> String {
    let cleaned =
      value
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return fallback }
    return StringUtils.boundedText(cleaned, limit: 80)
  }

  private static func rustStringLiteralContent(_ value: String) -> String {
    var escaped = ""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\\":
        escaped += "\\\\"
      case "\"":
        escaped += "\\\""
      case "\t":
        escaped += "\\t"
      default:
        if scalar.value < 0x20 {
          escaped += "\\u{\(String(scalar.value, radix: 16))}"
        } else {
          escaped.unicodeScalars.append(scalar)
        }
      }
    }
    return escaped
  }

  private static func gitignore() -> String {
    """
    /target/
    /.compass/visual-verify/
    .DS_Store
    """
  }

  private static func scaffoldMetadata() -> String {
    """
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
    productization_experience = true
    """
  }

  private static func workspaceManifest() -> String {
    """
    [workspace]
    resolver = "2"
    members = [
      "crates/app-core",
      "crates/app-cli",
      "crates/app-desktop",
      "xtask",
    ]

    [workspace.package]
    edition = "2021"
    license = "MIT"
    version = "0.1.0"

    [workspace.dependencies]
    app-core = { path = "crates/app-core" }
    base64 = "0.22"
    eframe = "0.29"
    image = { version = "0.25", default-features = false, features = ["png"] }
    serde = { version = "1", features = ["derive"] }
    serde_json = "1"
    """
  }

  private static func rustToolchain() -> String {
    """
    [toolchain]
    channel = "stable"
    components = ["rustfmt", "clippy"]
    """
  }

  private static func readme(projectName: String) -> String {
    """
    # \(projectName)

    This is the blessed Compass Rust workspace shape for generated projects.
    Compass itself remains a native Swift/macOS app; generated output lives here as Rust.
    The verification commands below mirror Compass factory engine behavior while
    staying self-contained in this generated Cargo workspace.

    ## Architecture

    - `crates/app-core`: deterministic state, pure domain logic, and schema data.
    - `crates/app-cli`: command-line entry point for inspection and automation.
    - `crates/app-desktop`: Rust desktop UI built with `eframe`/`egui`.
    - `xtask`: Rust-owned automation for checks and visual verification.
    - `schemas/`: generated-project contracts checked into the Rust workspace.

    ## Deterministic Simulation Contract

    Generated apps keep product behavior behind a pure `app-core` transition:
    `run_simulation(SimulationInput) -> SimulationSnapshot`. The default CLI
    exposes that contract with `app-cli simulate --input '<json>'` and prints
    stable pretty JSON. Treat this as the host-side fixture seam for future
    Murphy scenarios: inputs are explicit, outputs are serializable, and the
    desktop UI only renders state derived from the same deterministic core.

    ## Deterministic GUI Replay Contract

    Generated desktop behavior also has a semantic replay surface:
    `run_gui_replay(GuiReplayTrace) -> GuiSemanticSnapshot`. The default CLI
    exposes it with `app-cli gui-replay --input '<json>'` and emits stable JSON
    containing ordered semantic nodes, deterministic state, and replay events.
    `xtask visual-verify` captures both this semantic snapshot and a screenshot;
    use the semantic JSON as the replay/assertion target and the screenshot as
    human-facing rendering proof.

    ## Deterministic Productization Experience Contract

    Product experiments use `run_productization_experience(ProductizationExperienceInput) ->
    ProductizationExperienceTrace` as a semantic app journey. The input carries
    the pain, solution, experiment, current workflow, and alternatives being
    evaluated. The generated app owns the allowed action list for each state,
    and `app-cli productization-experience --input '<json>'` deterministically
    replays a supplied action prefix. Persona agents may choose only from the
    latest `allowedNextActions`; screenshots are optional supporting proof, not
    the assertion surface.

    Productization evidence is product pressure, not a release gate. Use
    `productization-smoke` to prove this generated app can replay a deterministic
    model-free product journey, then use a live persona model only for manual
    product review. Treat repeated objections and low scores as signals to
    investigate, not as automatic proof that the product is good or bad.

    Manual productization simulation checklist:
    - Confirm `app-cli productization-experience-schema` prints the expected contract.
    - Run `xtask productization-smoke` before involving a live model.
    - For live review, verify persona actions come only from `allowedNextActions`.
    - Keep feedback skeptical and structured; avoid optimizing for praise.
    - Inspect pain-relief summaries in Compass before changing the roadmap.

    ## Standard Commands

    - Format: `\(RustVerifyCommands.cargo(RustVerifyCommands.fmt))`
    - Lint: `\(RustVerifyCommands.cargo(RustVerifyCommands.clippy))`
    - Test: `\(RustVerifyCommands.cargo(RustVerifyCommands.test))`
    - Coverage: `\(RustVerifyCommands.cargo(RustVerifyCommands.coverage))`
    - Build: `\(RustVerifyCommands.cargo(RustVerifyCommands.build))`
    - Run CLI: `\(RustVerifyCommands.cargo(["run", "-p", "app-cli", "--", "status"]))`
    - Run simulation fixture: `\(RustVerifyCommands.cargo(["run", "-p", "app-cli", "--", "simulate", "--input", #"{"seed":"demo","ticks":3,"action":"advance"}"#]))`
    - Run GUI replay fixture: `\(RustVerifyCommands.cargo(["run", "-p", "app-cli", "--", "gui-replay", "--input", #"{"seed":"demo","steps":[{"action":"advance","ticks":2},{"action":"visual_input","value":"space"}]}"#]))`
    - Run productization experience fixture: `\(RustVerifyCommands.cargo(["run", "-p", "app-cli", "--", "productization-experience", "--input", #"{"schemaVersion":1,"pain":{"id":"pain-reporting","summary":"Weekly reporting takes too long","impact":"Managers lose visibility"},"solution":{"id":"solution-compass","title":"Compass workflow helper","promise":"Turn scattered updates into a reviewed weekly report"},"experiment":{"id":"experiment-reporting","branchName":"productization/reporting","successSignal":"Persona completes a report draft and sees why it beats the current workflow"},"scenario":{"seed":"demo","personaSummary":"Operations lead evaluating a workflow tool","task":"Reduce weekly reporting work"},"currentWorkflow":{"summary":"Collect updates manually, paste them into a spreadsheet, and chase missing details.","frictionPoints":["manual copy paste","late follow ups"]},"alternatives":[{"id":"spreadsheet","name":"Shared spreadsheet","description":"A manual tracker with copied status updates.","switchingObjection":"The team already knows the spreadsheet."}],"actions":[{"id":"inspect_pain","params":{}},{"id":"compare_current_alternative","params":{}},{"id":"start_solution_workflow","params":{}}]}"#]))`
    - Print productization experience schema: `\(RustVerifyCommands.cargo(["run", "-p", "app-cli", "--", "productization-experience-schema"]))`
    - Productization smoke: `\(RustVerifyCommands.cargo(RustVerifyCommands.productizationSmoke))`
    - Run desktop: `\(RustVerifyCommands.cargo(RustVerifyCommands.runDesktop))`
    - Fast verify: `\(RustVerifyCommands.cargo(RustVerifyCommands.fastVerify))`
    - Visual verify: `\(RustVerifyCommands.cargo(RustVerifyCommands.visualVerifyNoBase64))`
    - Visual verify with screenshot bytes: `\(RustProjectScaffold.visualVerifyCommand)`
    - Factory smoke: `\(RustProjectScaffold.factorySmokeCommand)`
    - Factory smoke with screenshot bytes: `\(RustProjectScaffold.factorySmokeWithScreenshotCommand)`
    - Engine parity check: `\(RustVerifyCommands.cargo(RustVerifyCommands.engineParityCheck))`

    `engine-parity-check` is retained as a compatibility alias for `factory-smoke`.
    Normal implementation verify should use the fast `xtask verify` tier; reserve
    `factory-smoke` for full factory proof that includes desktop visual verification.

    The desktop app uses deterministic demo state and stable window labels so Compass can
    build it in the Shared VM, launch it in the guest, wait for readiness, send a
    platform-neutral visual input request, capture a semantic GUI snapshot plus a
    Rust-rendered viewport artifact, and terminate it cleanly.
    """
  }

  private static func demoStateSchema() -> String {
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "DemoState",
      "type": "object",
      "required": ["headline", "completed", "total"],
      "properties": {
        "headline": { "type": "string" },
        "completed": { "type": "integer", "minimum": 0 },
        "total": { "type": "integer", "minimum": 1 }
      }
    }
    """
  }

  private static func simulationInputSchema() -> String {
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "SimulationInput",
      "type": "object",
      "required": ["seed", "ticks", "action"],
      "properties": {
        "seed": { "type": "string" },
        "ticks": { "type": "integer", "minimum": 0 },
        "action": { "type": "string", "enum": ["advance", "hold", "reset"] }
      }
    }
    """
  }

  private static func guiReplayTraceSchema() -> String {
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "GuiReplayTrace",
      "type": "object",
      "required": ["seed", "steps"],
      "properties": {
        "seed": { "type": "string" },
        "steps": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["action"],
            "properties": {
              "action": { "type": "string", "enum": ["advance", "hold", "reset", "visual_input"] },
              "ticks": { "type": "integer", "minimum": 0 },
              "value": { "type": "string" }
            }
          }
        }
      }
    }
    """
  }

  private static func productizationExperienceInputSchema() -> String {
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "ProductizationExperienceInput",
      "type": "object",
      "required": [
        "schemaVersion",
        "pain",
        "solution",
        "experiment",
        "scenario",
        "currentWorkflow",
        "alternatives",
        "actions"
      ],
      "properties": {
        "schemaVersion": { "type": "integer", "const": 1 },
        "pain": {
          "type": "object",
          "required": ["id", "summary", "impact"],
          "properties": {
            "id": { "type": "string" },
            "summary": { "type": "string" },
            "impact": { "type": "string" }
          }
        },
        "solution": {
          "type": "object",
          "required": ["id", "title", "promise"],
          "properties": {
            "id": { "type": "string" },
            "title": { "type": "string" },
            "promise": { "type": "string" }
          }
        },
        "experiment": {
          "type": "object",
          "required": ["id", "branchName", "successSignal"],
          "properties": {
            "id": { "type": "string" },
            "branchName": { "type": "string" },
            "successSignal": { "type": "string" }
          }
        },
        "scenario": {
          "type": "object",
          "required": ["seed", "personaSummary", "task"],
          "properties": {
            "seed": { "type": "string" },
            "personaSummary": { "type": "string" },
            "task": { "type": "string" }
          }
        },
        "currentWorkflow": {
          "type": "object",
          "required": ["summary", "frictionPoints"],
          "properties": {
            "summary": { "type": "string" },
            "frictionPoints": {
              "type": "array",
              "items": { "type": "string" }
            }
          }
        },
        "alternatives": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["id", "name", "description", "switchingObjection"],
            "properties": {
              "id": { "type": "string" },
              "name": { "type": "string" },
              "description": { "type": "string" },
              "switchingObjection": { "type": "string" }
            }
          }
        },
        "actions": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["id", "params"],
            "properties": {
              "id": { "type": "string" },
              "params": { "type": "object" }
            }
          }
        }
      }
    }
    """
  }

  private static func productizationExperienceTraceSchema() -> String {
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "ProductizationExperienceTrace",
      "type": "object",
      "required": [
        "schemaVersion",
        "painID",
        "solutionID",
        "experimentID",
        "initialState",
        "turns",
        "allowedNextActions",
        "terminalStatus",
        "eventLog",
        "painReliefSignals"
      ],
      "properties": {
        "schemaVersion": { "type": "integer", "const": 1 },
        "painID": { "type": "string" },
        "solutionID": { "type": "string" },
        "experimentID": { "type": "string" },
        "initialState": { "type": "object" },
        "turns": { "type": "array" },
        "allowedNextActions": { "type": "array" },
        "terminalStatus": {
          "type": "string",
          "enum": ["in_progress", "completed", "abandoned", "invalid_action"]
        },
        "eventLog": {
          "type": "array",
          "items": { "type": "string" }
        },
        "painReliefSignals": {
          "type": "object",
          "required": [
            "painRecognized",
            "workflowAdvanced",
            "currentAlternativeAddressed",
            "currentAlternativeComparison",
            "switchingObjectionReduced",
            "missingCapabilityIDs",
            "evidenceSummary"
          ],
          "properties": {
            "painRecognized": { "type": "boolean" },
            "workflowAdvanced": { "type": "boolean" },
            "currentAlternativeAddressed": { "type": "boolean" },
            "currentAlternativeComparison": { "type": "string" },
            "switchingObjectionReduced": { "type": "boolean" },
            "missingCapabilityIDs": {
              "type": "array",
              "items": { "type": "string" }
            },
            "evidenceSummary": { "type": "string" }
          }
        }
      }
    }
    """
  }

  private static func appCoreManifest() -> String {
    """
    [package]
    name = "app-core"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [dependencies]
    serde.workspace = true
    serde_json.workspace = true
    """
  }

  private static func appCoreLib() -> String {
    """
    use serde::{Deserialize, Serialize};
    use serde_json::{json, Value};

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct DemoState {
        pub headline: String,
        pub completed: u8,
        pub total: u8,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct SimulationInput {
        pub seed: String,
        pub ticks: u32,
        pub action: SimulationAction,
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "snake_case")]
    pub enum SimulationAction {
        Advance,
        Hold,
        Reset,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct SimulationSnapshot {
        pub state: DemoState,
        pub ticks_elapsed: u32,
        pub event_log: Vec<String>,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct GuiReplayTrace {
        pub seed: String,
        pub steps: Vec<GuiReplayStep>,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct GuiReplayStep {
        pub action: GuiReplayAction,
        #[serde(default)]
        pub ticks: u32,
        #[serde(default)]
        pub value: Option<String>,
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "snake_case")]
    pub enum GuiReplayAction {
        Advance,
        Hold,
        Reset,
        VisualInput,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct GuiSemanticSnapshot {
        pub schema_version: u8,
        pub state: DemoState,
        pub nodes: Vec<GuiNode>,
        pub replay_events: Vec<String>,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct GuiNode {
        pub id: String,
        pub role: String,
        pub text: String,
        pub state: String,
    }

    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProductizationExperienceInput {
        pub schema_version: u8,
        pub pain: ProductizationPain,
        pub solution: ProductizationSolution,
        pub experiment: ProductizationExperiment,
        pub scenario: ProductizationScenario,
        pub current_workflow: ProductizationCurrentWorkflow,
        #[serde(default)]
        pub alternatives: Vec<ProductizationAlternative>,
        #[serde(default)]
        pub actions: Vec<ProductizationExperienceAction>,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct ProductizationPain {
        pub id: String,
        pub summary: String,
        pub impact: String,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct ProductizationSolution {
        pub id: String,
        pub title: String,
        pub promise: String,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProductizationExperiment {
        pub id: String,
        pub branch_name: String,
        pub success_signal: String,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProductizationScenario {
        pub seed: String,
        pub persona_summary: String,
        pub task: String,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProductizationCurrentWorkflow {
        pub summary: String,
        pub friction_points: Vec<String>,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProductizationAlternative {
        pub id: String,
        pub name: String,
        pub description: String,
        pub switching_objection: String,
    }

    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    pub struct ProductizationExperienceAction {
        pub id: String,
        #[serde(default = "empty_params")]
        pub params: Value,
    }

    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProductizationExperienceAllowedAction {
        pub id: String,
        pub label: String,
        pub description: String,
        pub params_schema: Value,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProductizationExperienceState {
        pub id: String,
        pub headline: String,
        pub body: String,
        pub semantic_nodes: Vec<ProductizationExperienceNode>,
        pub observations: Vec<String>,
        pub terminal: bool,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    pub struct ProductizationExperienceNode {
        pub id: String,
        pub role: String,
        pub text: String,
    }

    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProductizationExperienceTurn {
        pub index: u32,
        pub action: ProductizationExperienceAction,
        pub state: ProductizationExperienceState,
        pub allowed_next_actions: Vec<ProductizationExperienceAllowedAction>,
        pub event_log: Vec<String>,
    }

    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct PainReliefSignals {
        pub pain_recognized: bool,
        pub workflow_advanced: bool,
        pub current_alternative_addressed: bool,
        pub current_alternative_comparison: String,
        pub switching_objection_reduced: bool,
        #[serde(rename = "missingCapabilityIDs")]
        pub missing_capability_ids: Vec<String>,
        pub evidence_summary: String,
    }

    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProductizationExperienceTrace {
        pub schema_version: u8,
        #[serde(rename = "painID")]
        pub pain_id: String,
        #[serde(rename = "solutionID")]
        pub solution_id: String,
        #[serde(rename = "experimentID")]
        pub experiment_id: String,
        pub initial_state: ProductizationExperienceState,
        pub turns: Vec<ProductizationExperienceTurn>,
        pub allowed_next_actions: Vec<ProductizationExperienceAllowedAction>,
        pub terminal_status: ProductizationExperienceTerminalStatus,
        pub event_log: Vec<String>,
        pub pain_relief_signals: PainReliefSignals,
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "snake_case")]
    pub enum ProductizationExperienceTerminalStatus {
        InProgress,
        Completed,
        Abandoned,
        InvalidAction,
    }

    #[derive(Debug, Clone)]
    struct ProductizationExperienceRuntime {
        state: ProductizationExperienceState,
        terminal_status: ProductizationExperienceTerminalStatus,
        event_log: Vec<String>,
        pain_recognized: bool,
        workflow_advanced: bool,
        current_alternative_addressed: bool,
        switching_objection_reduced: bool,
    }

    impl DemoState {
        pub fn deterministic(seed: &str) -> Self {
            let completed = 2 + (seed.bytes().fold(0_u8, u8::wrapping_add) % 2);
            Self {
                headline: "Rust workspace ready".to_owned(),
                completed,
                total: 4,
            }
        }

        pub fn completion_label(&self) -> String {
            format!("{}/{} checks ready", self.completed, self.total)
        }

        pub fn summary_line(&self) -> String {
            format!("{} - {}", self.headline, self.completion_label())
        }
    }

    impl Default for SimulationInput {
        fn default() -> Self {
            Self {
                seed: "cli".to_owned(),
                ticks: 1,
                action: SimulationAction::Advance,
            }
        }
    }

    pub fn run_simulation(input: SimulationInput) -> SimulationSnapshot {
        let mut state = DemoState::deterministic(&input.seed);
        let mut event_log = Vec::new();
        event_log.push(format!("seed:{}", input.seed));
        event_log.push(format!("ticks:{}", input.ticks));

        match input.action {
            SimulationAction::Advance => {
                let budget = state.total.saturating_sub(state.completed);
                let delta = budget.min((input.ticks % 3) as u8);
                state.completed += delta;
                event_log.push(format!("action:advance:{delta}"));
            }
            SimulationAction::Hold => {
                event_log.push("action:hold:0".to_owned());
            }
            SimulationAction::Reset => {
                state.completed = 0;
                event_log.push("action:reset:0".to_owned());
            }
        }

        SimulationSnapshot {
            state,
            ticks_elapsed: input.ticks,
            event_log,
        }
    }

    impl Default for GuiReplayTrace {
        fn default() -> Self {
            Self {
                seed: "gui".to_owned(),
                steps: vec![GuiReplayStep {
                    action: GuiReplayAction::Advance,
                    ticks: 1,
                    value: None,
                }],
            }
        }
    }

    pub fn run_gui_replay(trace: GuiReplayTrace) -> GuiSemanticSnapshot {
        let mut state = DemoState::deterministic(&trace.seed);
        let mut replay_events = vec![format!("seed:{}", trace.seed)];
        let mut input_status = "not requested".to_owned();

        for (index, step) in trace.steps.into_iter().enumerate() {
            match step.action {
                GuiReplayAction::Advance => {
                    let snapshot = run_simulation(SimulationInput {
                        seed: format!("{}:{index}", state.headline),
                        ticks: step.ticks,
                        action: SimulationAction::Advance,
                    });
                    state.completed = snapshot.state.completed;
                    replay_events.push(format!("step:{index}:advance:{}", step.ticks));
                }
                GuiReplayAction::Hold => {
                    replay_events.push(format!("step:{index}:hold:{}", step.ticks));
                }
                GuiReplayAction::Reset => {
                    state.completed = 0;
                    replay_events.push(format!("step:{index}:reset"));
                }
                GuiReplayAction::VisualInput => {
                    let value = step.value.unwrap_or_else(|| "unknown".to_owned());
                    input_status = format!("acknowledged:{value}");
                    replay_events.push(format!("step:{index}:visual_input:{value}"));
                }
            }
        }

        gui_semantic_snapshot(state, input_status, replay_events)
    }

    impl Default for ProductizationExperienceInput {
        fn default() -> Self {
            Self {
                schema_version: 1,
                pain: ProductizationPain {
                    id: "pain-reporting".to_owned(),
                    summary: "Weekly reporting takes too long".to_owned(),
                    impact: "Managers lose visibility and operators spend Friday chasing updates"
                        .to_owned(),
                },
                solution: ProductizationSolution {
                    id: "solution-compass".to_owned(),
                    title: "Compass workflow helper".to_owned(),
                    promise: "Turn scattered updates into a reviewed weekly report".to_owned(),
                },
                experiment: ProductizationExperiment {
                    id: "experiment-reporting".to_owned(),
                    branch_name: "productization/reporting".to_owned(),
                    success_signal:
                        "Persona completes a report draft and sees why it beats the current workflow"
                            .to_owned(),
                },
                scenario: ProductizationScenario {
                    seed: "demo".to_owned(),
                    persona_summary: "Operations lead evaluating a workflow tool".to_owned(),
                    task: "Reduce weekly reporting work".to_owned(),
                },
                current_workflow: ProductizationCurrentWorkflow {
                    summary:
                        "Collect updates manually, paste them into a spreadsheet, and chase missing details"
                            .to_owned(),
                    friction_points: vec![
                        "manual copy paste".to_owned(),
                        "late follow ups".to_owned(),
                    ],
                },
                alternatives: vec![ProductizationAlternative {
                    id: "spreadsheet".to_owned(),
                    name: "Shared spreadsheet".to_owned(),
                    description: "A manual tracker with copied status updates.".to_owned(),
                    switching_objection: "The team already knows the spreadsheet.".to_owned(),
                }],
                actions: Vec::new(),
            }
        }
    }

    pub fn run_productization_experience(
        input: ProductizationExperienceInput,
    ) -> ProductizationExperienceTrace {
        let mut runtime = ProductizationExperienceRuntime {
            state: initial_productization_experience_state(&input),
            terminal_status: ProductizationExperienceTerminalStatus::InProgress,
            event_log: vec![
                format!("pain:{}", input.pain.id),
                format!("solution:{}", input.solution.id),
                format!("experiment:{}", input.experiment.id),
                format!("scenario_seed:{}", input.scenario.seed),
            ],
            pain_recognized: false,
            workflow_advanced: false,
            current_alternative_addressed: false,
            switching_objection_reduced: false,
        };
        let initial_state = runtime.state.clone();
        let mut turns = Vec::new();

        for (index, action) in input.actions.iter().cloned().enumerate() {
            let allowed_before = allowed_productization_experience_actions(&runtime);
            let turn_events = if allowed_before.iter().any(|allowed| allowed.id == action.id) {
                apply_productization_experience_action(&mut runtime, &input, &action, index)
            } else {
                runtime.terminal_status = ProductizationExperienceTerminalStatus::InvalidAction;
                runtime.state = productization_experience_state(
                    "invalid_action",
                    "Invalid action rejected",
                    format!(
                        "The app does not allow `{}` from state `{}`.",
                        action.id, runtime.state.id
                    ),
                    vec!["invalid action".to_owned()],
                    true,
                );
                vec![format!("turn:{index}:invalid_action:{}", action.id)]
            };
            runtime.event_log.extend(turn_events.clone());
            let allowed_next_actions = allowed_productization_experience_actions(&runtime);
            turns.push(ProductizationExperienceTurn {
                index: index as u32,
                action,
                state: runtime.state.clone(),
                allowed_next_actions,
                event_log: turn_events,
            });
            if runtime.terminal_status != ProductizationExperienceTerminalStatus::InProgress {
                break;
            }
        }

        let pain_relief_signals = pain_relief_signals(&runtime, &input);
        ProductizationExperienceTrace {
            schema_version: 1,
            pain_id: input.pain.id,
            solution_id: input.solution.id,
            experiment_id: input.experiment.id,
            initial_state,
            turns,
            allowed_next_actions: allowed_productization_experience_actions(&runtime),
            terminal_status: runtime.terminal_status,
            event_log: runtime.event_log,
            pain_relief_signals,
        }
    }

    fn initial_productization_experience_state(
        input: &ProductizationExperienceInput,
    ) -> ProductizationExperienceState {
        productization_experience_state(
            "initial",
            "Ready to evaluate pain relief",
            format!(
                "{} is trying to: {}. Current workflow: {}. Proposed solution: {}.",
                input.scenario.persona_summary,
                input.scenario.task,
                input.current_workflow.summary,
                input.solution.promise
            ),
            vec![
                format!("pain visible: {}", input.pain.summary),
                "solution workflow entry point visible".to_owned(),
                format!("alternatives available: {}", input.alternatives.len()),
            ],
            false,
        )
    }

    fn apply_productization_experience_action(
        runtime: &mut ProductizationExperienceRuntime,
        input: &ProductizationExperienceInput,
        action: &ProductizationExperienceAction,
        index: usize,
    ) -> Vec<String> {
        match action.id.as_str() {
            "inspect_pain" => {
                runtime.pain_recognized = true;
                runtime.state = productization_experience_state(
                    "pain_inspected",
                    "Pain inspected",
                    format!(
                        "The app names `{}` and explains the impact: {}.",
                        input.pain.summary, input.pain.impact
                    ),
                    vec![
                        "pain named".to_owned(),
                        "impact visible".to_owned(),
                        "solution proof still requested".to_owned(),
                    ],
                    false,
                );
                vec![format!("turn:{index}:inspect_pain")]
            }
            "compare_current_alternative" => {
                runtime.current_alternative_addressed = true;
                runtime.state = productization_experience_state(
                    "alternative_compared",
                    "Current alternative compared",
                    format!(
                        "The app compares `{}` with `{}` and invites a switching objection: {}",
                        input.solution.title,
                        current_alternative_label(input),
                        current_switching_objection(input)
                    ),
                    vec![
                        "alternative named".to_owned(),
                        "switching objection invited".to_owned(),
                    ],
                    false,
                );
                vec![format!("turn:{index}:compare_current_alternative")]
            }
            "reduce_switching_objection" => {
                runtime.switching_objection_reduced = true;
                runtime.current_alternative_addressed = true;
                runtime.state = productization_experience_state(
                    "switching_objection_reduced",
                    "Switching objection reduced",
                    format!(
                        "The app answers why leaving `{}` is worth testing for this experiment.",
                        current_alternative_label(input)
                    ),
                    vec![
                        "switching objection acknowledged".to_owned(),
                        "experiment-sized switch framed".to_owned(),
                    ],
                    false,
                );
                vec![format!("turn:{index}:reduce_switching_objection")]
            }
            "start_solution_workflow" => {
                runtime.workflow_advanced = true;
                runtime.state = productization_experience_state(
                    "workflow_started",
                    "Solution workflow started",
                    format!(
                        "The app starts `{}` and asks for one concrete input before it can show pain relief.",
                        input.solution.title
                    ),
                    vec![
                        "workflow entry accepted".to_owned(),
                        "requested input visible".to_owned(),
                    ],
                    false,
                );
                vec![format!("turn:{index}:start_solution_workflow")]
            }
            "provide_requested_input" => {
                runtime.workflow_advanced = true;
                runtime.terminal_status = ProductizationExperienceTerminalStatus::Completed;
                runtime.state = productization_experience_state(
                    "workflow_completed",
                    "Pain relief outcome shown",
                    format!(
                        "The app returns a deterministic outcome for `{}` that can be compared with `{}`.",
                        input.experiment.success_signal,
                        current_alternative_label(input)
                    ),
                    vec![
                        "workflow completed".to_owned(),
                        "outcome ready for feedback".to_owned(),
                    ],
                    true,
                );
                vec![format!("turn:{index}:provide_requested_input")]
            }
            "ask_for_help" => {
                runtime.state = productization_experience_state(
                    "help_requested",
                    "Help requested",
                    "The app explains the next step but still expects the persona to judge whether the pain relief is concrete.",
                    vec![
                        "help surfaced".to_owned(),
                        "next action clarified".to_owned(),
                    ],
                    false,
                );
                vec![format!("turn:{index}:ask_for_help")]
            }
            "abandon_task" => {
                runtime.terminal_status = ProductizationExperienceTerminalStatus::Abandoned;
                runtime.state = productization_experience_state(
                    "abandoned",
                    "Task abandoned",
                    "The persona left the flow before the app proved enough pain relief.",
                    vec!["task abandoned".to_owned()],
                    true,
                );
                vec![format!("turn:{index}:abandon_task")]
            }
            _ => unreachable!("caller validates allowed productization actions"),
        }
    }

    fn allowed_productization_experience_actions(
        runtime: &ProductizationExperienceRuntime,
    ) -> Vec<ProductizationExperienceAllowedAction> {
        if runtime.terminal_status != ProductizationExperienceTerminalStatus::InProgress
            || runtime.state.terminal
        {
            return Vec::new();
        }
        match runtime.state.id.as_str() {
            "initial" => vec![
                allowed_action(
                    "inspect_pain",
                    "Inspect pain",
                    "Read the pain and impact this experiment is meant to relieve.",
                ),
                allowed_action(
                    "compare_current_alternative",
                    "Compare current alternative",
                    "Judge the solution against the current workflow or workaround.",
                ),
                allowed_action(
                    "start_solution_workflow",
                    "Start solution workflow",
                    "Try the main workflow exposed by the app.",
                ),
                allowed_action(
                    "ask_for_help",
                    "Ask for help",
                    "Request clarification about what to do next.",
                ),
                allowed_action(
                    "abandon_task",
                    "Abandon task",
                    "Stop because pain relief is not clear.",
                ),
            ],
            "pain_inspected" | "help_requested" => vec![
                allowed_action(
                    "compare_current_alternative",
                    "Compare current alternative",
                    "Judge the solution against the current workflow or workaround.",
                ),
                allowed_action(
                    "start_solution_workflow",
                    "Start solution workflow",
                    "Try the main workflow exposed by the app.",
                ),
                allowed_action(
                    "ask_for_help",
                    "Ask for help",
                    "Request clarification about what to do next.",
                ),
                allowed_action(
                    "abandon_task",
                    "Abandon task",
                    "Stop because pain relief is not clear.",
                ),
            ],
            "alternative_compared" => vec![
                allowed_action(
                    "reduce_switching_objection",
                    "Reduce switching objection",
                    "See whether the app answers why switching is worth testing.",
                ),
                allowed_action(
                    "start_solution_workflow",
                    "Start solution workflow",
                    "Try the main workflow exposed by the app.",
                ),
                allowed_action(
                    "ask_for_help",
                    "Ask for help",
                    "Request clarification about what to do next.",
                ),
                allowed_action(
                    "abandon_task",
                    "Abandon task",
                    "Stop because pain relief is not clear.",
                ),
            ],
            "switching_objection_reduced" => vec![
                allowed_action(
                    "start_solution_workflow",
                    "Start solution workflow",
                    "Try the main workflow exposed by the app.",
                ),
                allowed_action(
                    "ask_for_help",
                    "Ask for help",
                    "Request clarification about what to do next.",
                ),
                allowed_action(
                    "abandon_task",
                    "Abandon task",
                    "Stop because pain relief is not clear.",
                ),
            ],
            "workflow_started" => vec![
                allowed_action(
                    "provide_requested_input",
                    "Provide requested input",
                    "Supply the concrete input the workflow requests.",
                ),
                allowed_action(
                    "ask_for_help",
                    "Ask for help",
                    "Request clarification before providing input.",
                ),
                allowed_action(
                    "abandon_task",
                    "Abandon task",
                    "Stop because pain relief is not clear.",
                ),
            ],
            _ => Vec::new(),
        }
    }

    fn pain_relief_signals(
        runtime: &ProductizationExperienceRuntime,
        input: &ProductizationExperienceInput,
    ) -> PainReliefSignals {
        let mut missing_capability_ids = Vec::new();
        if !runtime.pain_recognized {
            missing_capability_ids.push("pain_recognition".to_owned());
        }
        if !runtime.workflow_advanced {
            missing_capability_ids.push("workflow_advancement".to_owned());
        }
        if !runtime.current_alternative_addressed {
            missing_capability_ids.push("current_alternative_comparison".to_owned());
        }
        if !runtime.switching_objection_reduced {
            missing_capability_ids.push("switching_objection_reduction".to_owned());
        }
        if input.alternatives.is_empty() {
            missing_capability_ids.push("named_current_alternative".to_owned());
        }

        let evidence_summary = if missing_capability_ids.is_empty() {
            format!(
                "The trace recognizes `{}`, advances the solution workflow, compares against `{}`, and reduces the switching objection.",
                input.pain.summary,
                current_alternative_label(input)
            )
        } else {
            format!(
                "The trace partially evaluates `{}`; missing deterministic proof for {}.",
                input.pain.summary,
                missing_capability_ids.join(", ")
            )
        };
        let current_alternative_comparison = if runtime.current_alternative_addressed {
            format!(
                "Compared `{}` against `{}`; switching objection: {}",
                input.solution.title,
                current_alternative_label(input),
                current_switching_objection(input)
            )
        } else {
            format!(
                "No current-alternative comparison recorded for `{}`.",
                current_alternative_label(input)
            )
        };

        PainReliefSignals {
            pain_recognized: runtime.pain_recognized,
            workflow_advanced: runtime.workflow_advanced,
            current_alternative_addressed: runtime.current_alternative_addressed,
            current_alternative_comparison,
            switching_objection_reduced: runtime.switching_objection_reduced,
            missing_capability_ids,
            evidence_summary,
        }
    }

    fn allowed_action(
        id: &str,
        label: &str,
        description: &str,
    ) -> ProductizationExperienceAllowedAction {
        ProductizationExperienceAllowedAction {
            id: id.to_owned(),
            label: label.to_owned(),
            description: description.to_owned(),
            params_schema: json!({
                "type": "object",
                "additionalProperties": true
            }),
        }
    }

    fn productization_experience_state(
        id: &str,
        headline: impl Into<String>,
        body: impl Into<String>,
        observations: Vec<String>,
        terminal: bool,
    ) -> ProductizationExperienceState {
        let headline = headline.into();
        let body = body.into();
        ProductizationExperienceState {
            id: id.to_owned(),
            semantic_nodes: vec![
                ProductizationExperienceNode {
                    id: "screen.headline".to_owned(),
                    role: "heading".to_owned(),
                    text: headline.clone(),
                },
                ProductizationExperienceNode {
                    id: "screen.body".to_owned(),
                    role: "text".to_owned(),
                    text: body.clone(),
                },
            ],
            headline,
            body,
            observations,
            terminal,
        }
    }

    fn current_alternative_label(input: &ProductizationExperienceInput) -> String {
        input
            .alternatives
            .first()
            .map(|alternative| alternative.name.clone())
            .unwrap_or_else(|| input.current_workflow.summary.clone())
    }

    fn current_switching_objection(input: &ProductizationExperienceInput) -> String {
        input
            .alternatives
            .first()
            .map(|alternative| alternative.switching_objection.clone())
            .unwrap_or_else(|| "No named alternative was provided.".to_owned())
    }

    fn empty_params() -> Value {
        json!({})
    }

    pub fn gui_semantic_snapshot(
        state: DemoState,
        input_status: String,
        replay_events: Vec<String>,
    ) -> GuiSemanticSnapshot {
        GuiSemanticSnapshot {
            schema_version: 1,
            nodes: vec![
                GuiNode {
                    id: "root.heading".to_owned(),
                    role: "heading".to_owned(),
                    text: "Compass Rust Desktop".to_owned(),
                    state: "visible".to_owned(),
                },
                GuiNode {
                    id: "status.project_health".to_owned(),
                    role: "status".to_owned(),
                    text: state.completion_label(),
                    state: "visible".to_owned(),
                },
                GuiNode {
                    id: "summary.line".to_owned(),
                    role: "text".to_owned(),
                    text: state.summary_line(),
                    state: "visible".to_owned(),
                },
                GuiNode {
                    id: "input.status".to_owned(),
                    role: "status".to_owned(),
                    text: input_status,
                    state: "visible".to_owned(),
                },
            ],
            state,
            replay_events,
        }
    }

    pub fn demo_state_schema() -> Value {
        json!({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "DemoState",
            "type": "object",
            "required": ["headline", "completed", "total"],
            "properties": {
                "headline": { "type": "string" },
                "completed": { "type": "integer", "minimum": 0 },
                "total": { "type": "integer", "minimum": 1 }
            }
        })
    }

    pub fn simulation_input_schema() -> Value {
        json!({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "SimulationInput",
            "type": "object",
            "required": ["seed", "ticks", "action"],
            "properties": {
                "seed": { "type": "string" },
                "ticks": { "type": "integer", "minimum": 0 },
                "action": { "type": "string", "enum": ["advance", "hold", "reset"] }
            }
        })
    }

    pub fn gui_replay_trace_schema() -> Value {
        json!({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "GuiReplayTrace",
            "type": "object",
            "required": ["seed", "steps"],
            "properties": {
                "seed": { "type": "string" },
                "steps": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "required": ["action"],
                        "properties": {
                            "action": {
                                "type": "string",
                                "enum": ["advance", "hold", "reset", "visual_input"]
                            },
                            "ticks": { "type": "integer", "minimum": 0 },
                            "value": { "type": "string" }
                        }
                    }
                }
            }
        })
    }

    pub fn productization_experience_input_schema() -> Value {
        json!({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "ProductizationExperienceInput",
            "type": "object",
            "required": [
                "schemaVersion",
                "pain",
                "solution",
                "experiment",
                "scenario",
                "currentWorkflow",
                "alternatives",
                "actions"
            ],
            "properties": {
                "schemaVersion": { "type": "integer", "const": 1 },
                "pain": {
                    "type": "object",
                    "required": ["id", "summary", "impact"],
                    "properties": {
                        "id": { "type": "string" },
                        "summary": { "type": "string" },
                        "impact": { "type": "string" }
                    }
                },
                "solution": {
                    "type": "object",
                    "required": ["id", "title", "promise"],
                    "properties": {
                        "id": { "type": "string" },
                        "title": { "type": "string" },
                        "promise": { "type": "string" }
                    }
                },
                "experiment": {
                    "type": "object",
                    "required": ["id", "branchName", "successSignal"],
                    "properties": {
                        "id": { "type": "string" },
                        "branchName": { "type": "string" },
                        "successSignal": { "type": "string" }
                    }
                },
                "scenario": {
                    "type": "object",
                    "required": ["seed", "personaSummary", "task"],
                    "properties": {
                        "seed": { "type": "string" },
                        "personaSummary": { "type": "string" },
                        "task": { "type": "string" }
                    }
                },
                "currentWorkflow": {
                    "type": "object",
                    "required": ["summary", "frictionPoints"],
                    "properties": {
                        "summary": { "type": "string" },
                        "frictionPoints": {
                            "type": "array",
                            "items": { "type": "string" }
                        }
                    }
                },
                "alternatives": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "required": ["id", "name", "description", "switchingObjection"],
                        "properties": {
                            "id": { "type": "string" },
                            "name": { "type": "string" },
                            "description": { "type": "string" },
                            "switchingObjection": { "type": "string" }
                        }
                    }
                },
                "actions": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "required": ["id", "params"],
                        "properties": {
                            "id": { "type": "string" },
                            "params": { "type": "object" }
                        }
                    }
                }
            }
        })
    }

    pub fn productization_experience_trace_schema() -> Value {
        json!({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "ProductizationExperienceTrace",
            "type": "object",
            "required": [
                "schemaVersion",
                "painID",
                "solutionID",
                "experimentID",
                "initialState",
                "turns",
                "allowedNextActions",
                "terminalStatus",
                "eventLog",
                "painReliefSignals"
            ],
            "properties": {
                "schemaVersion": { "type": "integer", "const": 1 },
                "painID": { "type": "string" },
                "solutionID": { "type": "string" },
                "experimentID": { "type": "string" },
                "initialState": { "type": "object" },
                "turns": { "type": "array" },
                "allowedNextActions": { "type": "array" },
                "terminalStatus": {
                    "type": "string",
                    "enum": ["in_progress", "completed", "abandoned", "invalid_action"]
                },
                "eventLog": {
                    "type": "array",
                    "items": { "type": "string" }
                },
                "painReliefSignals": {
                    "type": "object",
                    "required": [
                        "painRecognized",
                        "workflowAdvanced",
                        "currentAlternativeAddressed",
                        "currentAlternativeComparison",
                        "switchingObjectionReduced",
                        "missingCapabilityIDs",
                        "evidenceSummary"
                    ],
                    "properties": {
                        "painRecognized": { "type": "boolean" },
                        "workflowAdvanced": { "type": "boolean" },
                        "currentAlternativeAddressed": { "type": "boolean" },
                        "currentAlternativeComparison": { "type": "string" },
                        "switchingObjectionReduced": { "type": "boolean" },
                        "missingCapabilityIDs": {
                            "type": "array",
                            "items": { "type": "string" }
                        },
                        "evidenceSummary": { "type": "string" }
                    }
                }
            }
        })
    }

    pub fn productization_experience_contract_schema() -> Value {
        json!({
            "schemaVersion": 1,
            "input": productization_experience_input_schema(),
            "trace": productization_experience_trace_schema()
        })
    }

    """
  }

  private static func appCoreTests() -> String {
    """
    use app_core::{
        run_gui_replay, run_productization_experience, run_simulation, DemoState, GuiReplayAction,
        GuiReplayStep, GuiReplayTrace, ProductizationAlternative, ProductizationCurrentWorkflow,
        ProductizationExperienceAction, ProductizationExperienceInput,
        ProductizationExperienceTerminalStatus, ProductizationExperiment, ProductizationPain,
        ProductizationScenario, ProductizationSolution, SimulationAction, SimulationInput,
    };
    use serde_json::json;

    #[test]
    fn deterministic_state_has_stable_labels() {
        let state = DemoState::deterministic("compass-demo");

        assert_eq!(state.headline, "Rust workspace ready");
        assert!(state.completion_label().contains("checks ready"));
    }

    #[test]
    fn simulation_fixture_is_a_pure_transition() {
        let input = SimulationInput {
            seed: "case-a".to_owned(),
            ticks: 5,
            action: SimulationAction::Advance,
        };

        let first = run_simulation(input.clone());
        let second = run_simulation(input);

        assert_eq!(first, second);
        assert_eq!(first.ticks_elapsed, 5);
        assert_eq!(
            first.event_log,
            ["seed:case-a", "ticks:5", "action:advance:2"]
        );
    }

    #[test]
    fn gui_replay_fixture_emits_stable_semantic_snapshot() {
        let trace = GuiReplayTrace {
            seed: "gui-case".to_owned(),
            steps: vec![
                GuiReplayStep {
                    action: GuiReplayAction::Advance,
                    ticks: 2,
                    value: None,
                },
                GuiReplayStep {
                    action: GuiReplayAction::VisualInput,
                    ticks: 0,
                    value: Some("space".to_owned()),
                },
            ],
        };

        let first = run_gui_replay(trace.clone());
        let second = run_gui_replay(trace);

        assert_eq!(first, second);
        assert_eq!(first.schema_version, 1);
        assert!(first
            .nodes
            .iter()
            .any(|node| node.id == "input.status" && node.text == "acknowledged:space"));
    }

    #[test]
    fn productization_experience_fixture_replays_allowed_actions_deterministically() {
        let input = ProductizationExperienceInput {
            schema_version: 1,
            pain: ProductizationPain {
                id: "pain-reporting".to_owned(),
                summary: "Weekly reporting takes too long".to_owned(),
                impact: "Managers lack timely visibility".to_owned(),
            },
            solution: ProductizationSolution {
                id: "solution-reporting".to_owned(),
                title: "Reporting helper".to_owned(),
                promise: "Generate a reviewed weekly report from scattered updates".to_owned(),
            },
            experiment: ProductizationExperiment {
                id: "experiment-reporting".to_owned(),
                branch_name: "productization/reporting".to_owned(),
                success_signal: "Persona completes a report draft".to_owned(),
            },
            scenario: ProductizationScenario {
                seed: "productization-case".to_owned(),
                persona_summary: "Operations lead evaluating reporting workflow".to_owned(),
                task: "Try the core workflow".to_owned(),
            },
            current_workflow: ProductizationCurrentWorkflow {
                summary: "Manual spreadsheet and follow-up messages".to_owned(),
                friction_points: vec!["copy paste".to_owned(), "late follow ups".to_owned()],
            },
            alternatives: vec![ProductizationAlternative {
                id: "spreadsheet".to_owned(),
                name: "Shared spreadsheet".to_owned(),
                description: "Existing reporting tracker".to_owned(),
                switching_objection: "The team already knows it".to_owned(),
            }],
            actions: vec![
                ProductizationExperienceAction {
                    id: "inspect_pain".to_owned(),
                    params: json!({}),
                },
                ProductizationExperienceAction {
                    id: "compare_current_alternative".to_owned(),
                    params: json!({}),
                },
                ProductizationExperienceAction {
                    id: "reduce_switching_objection".to_owned(),
                    params: json!({}),
                },
                ProductizationExperienceAction {
                    id: "start_solution_workflow".to_owned(),
                    params: json!({}),
                },
            ],
        };

        let first = run_productization_experience(input.clone());
        let second = run_productization_experience(input);

        assert_eq!(first, second);
        assert_eq!(first.schema_version, 1);
        assert_eq!(first.pain_id, "pain-reporting");
        assert_eq!(first.turns.len(), 4);
        assert_eq!(
            first.terminal_status,
            ProductizationExperienceTerminalStatus::InProgress
        );
        assert!(first.pain_relief_signals.pain_recognized);
        assert!(first.pain_relief_signals.current_alternative_addressed);
        assert!(first
            .pain_relief_signals
            .current_alternative_comparison
            .contains("Shared spreadsheet"));
        assert!(first.pain_relief_signals.switching_objection_reduced);
        assert!(first
            .allowed_next_actions
            .iter()
            .any(|action| action.id == "provide_requested_input"));
    }

    """
  }

  private static func appCLIManifest() -> String {
    """
    [package]
    name = "app-cli"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [dependencies]
    app-core.workspace = true
    serde_json.workspace = true
    """
  }

  private static func appCLIMain() -> String {
    """
    use app_core::{
        demo_state_schema, gui_replay_trace_schema, productization_experience_contract_schema,
        run_gui_replay, run_productization_experience, run_simulation, simulation_input_schema,
        DemoState, GuiReplayTrace, ProductizationExperienceInput, SimulationInput,
    };

    fn main() -> Result<(), Box<dyn std::error::Error>> {
        let mut args = std::env::args().skip(1);
        match args.next().as_deref() {
            None | Some("status") => {
                println!("{}", DemoState::deterministic("cli").summary_line());
            }
            Some("schema") => {
                println!("{}", serde_json::to_string_pretty(&demo_state_schema())?);
            }
            Some("simulation-schema") => {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&simulation_input_schema())?
                );
            }
            Some("gui-replay-schema") => {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&gui_replay_trace_schema())?
                );
            }
            Some("productization-experience-schema") => {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&productization_experience_contract_schema())?
                );
            }
            Some("simulate") => {
                let input = parse_simulation_input(args)?;
                println!("{}", serde_json::to_string_pretty(&run_simulation(input))?);
            }
            Some("gui-replay") => {
                let trace = parse_gui_replay_trace(args)?;
                println!("{}", serde_json::to_string_pretty(&run_gui_replay(trace))?);
            }
            Some("productization-experience") => {
                let input = parse_productization_experience_input(args)?;
                println!(
                    "{}",
                    serde_json::to_string_pretty(&run_productization_experience(input))?
                );
            }
            Some(other) => {
                eprintln!("unknown command: {other}");
                eprintln!("usage: app-cli [status|schema|simulation-schema|gui-replay-schema|productization-experience-schema|simulate --input <json>|gui-replay --input <json>|productization-experience --input <json>]");
                std::process::exit(2);
            }
        }
        Ok(())
    }

    fn parse_simulation_input(
        mut args: impl Iterator<Item = String>,
    ) -> Result<SimulationInput, Box<dyn std::error::Error>> {
        let mut input_json = None;
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--input" => {
                    input_json = args.next();
                }
                other => {
                    return Err(format!("unknown simulate argument: {other}").into());
                }
            }
        }
        match input_json {
            Some(value) => Ok(serde_json::from_str(&value)?),
            None => Ok(SimulationInput::default()),
        }
    }

    fn parse_gui_replay_trace(
        mut args: impl Iterator<Item = String>,
    ) -> Result<GuiReplayTrace, Box<dyn std::error::Error>> {
        let mut input_json = None;
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--input" => {
                    input_json = args.next();
                }
                other => {
                    return Err(format!("unknown gui-replay argument: {other}").into());
                }
            }
        }
        match input_json {
            Some(value) => Ok(serde_json::from_str(&value)?),
            None => Ok(GuiReplayTrace::default()),
        }
    }

    fn parse_productization_experience_input(
        mut args: impl Iterator<Item = String>,
    ) -> Result<ProductizationExperienceInput, Box<dyn std::error::Error>> {
        let mut input_json = None;
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--input" => {
                    input_json = args.next();
                }
                other => {
                    return Err(format!("unknown productization-experience argument: {other}").into());
                }
            }
        }
        match input_json {
            Some(value) => Ok(serde_json::from_str(&value)?),
            None => Ok(ProductizationExperienceInput::default()),
        }
    }

    """
  }

  private static func appDesktopManifest() -> String {
    """
    [package]
    name = "app-desktop"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [dependencies]
    app-core.workspace = true
    eframe.workspace = true
    image.workspace = true
    serde_json.workspace = true
    """
  }

  private static func appDesktopMain(windowTitle: String) -> String {
    """
    use app_core::{gui_semantic_snapshot, DemoState};
    use eframe::egui;
    use std::path::{Path, PathBuf};
    use std::time::Duration;

    #[derive(Clone)]
    struct LaunchConfig {
        seed: String,
        ready_file: Option<PathBuf>,
        pid_file: Option<PathBuf>,
        screenshot_file: Option<PathBuf>,
        input_file: Option<PathBuf>,
        input_ack_file: Option<PathBuf>,
        semantic_snapshot_file: Option<PathBuf>,
        window_title: String,
    }

    impl LaunchConfig {
        fn parse() -> Self {
            let mut seed = "desktop".to_owned();
            let mut ready_file = None;
            let mut pid_file = None;
            let mut screenshot_file = None;
            let mut input_file = None;
            let mut input_ack_file = None;
            let mut semantic_snapshot_file = None;
            let mut args = std::env::args().skip(1);
            while let Some(arg) = args.next() {
                match arg.as_str() {
                    "--demo-seed" => {
                        if let Some(value) = args.next() {
                            seed = value;
                        }
                    }
                    "--visual-ready-file" => {
                        if let Some(value) = args.next() {
                            ready_file = Some(PathBuf::from(value));
                        }
                    }
                    "--visual-pid-file" => {
                        if let Some(value) = args.next() {
                            pid_file = Some(PathBuf::from(value));
                        }
                    }
                    "--visual-screenshot-file" => {
                        if let Some(value) = args.next() {
                            screenshot_file = Some(PathBuf::from(value));
                        }
                    }
                    "--visual-input-file" => {
                        if let Some(value) = args.next() {
                            input_file = Some(PathBuf::from(value));
                        }
                    }
                    "--visual-input-ack-file" => {
                        if let Some(value) = args.next() {
                            input_ack_file = Some(PathBuf::from(value));
                        }
                    }
                    "--visual-semantic-snapshot-file" => {
                        if let Some(value) = args.next() {
                            semantic_snapshot_file = Some(PathBuf::from(value));
                        }
                    }
                    _ => {}
                }
            }
            Self {
                seed,
                ready_file,
                pid_file,
                screenshot_file,
                input_file,
                input_ack_file,
                semantic_snapshot_file,
                window_title: "\(rustStringLiteralContent(windowTitle))".to_owned(),
            }
        }
    }

    fn main() -> eframe::Result<()> {
        let config = LaunchConfig::parse();
        write_pid_file(config.pid_file.as_ref());
        let title = config.window_title.clone();
        let options = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default()
                .with_inner_size([860.0, 540.0])
                .with_title(title.clone()),
            ..Default::default()
        };

        eframe::run_native(
            &title,
            options,
            Box::new(move |_cc| Ok(Box::new(CompassRustApp::new(config.clone())))),
        )
    }

    struct CompassRustApp {
        state: DemoState,
        ready_file: Option<PathBuf>,
        screenshot_file: Option<PathBuf>,
        input_file: Option<PathBuf>,
        input_ack_file: Option<PathBuf>,
        semantic_snapshot_file: Option<PathBuf>,
        input_observed: bool,
        wrote_ready: bool,
        wrote_semantic_snapshot: bool,
        requested_screenshot: bool,
        wrote_screenshot: bool,
    }

    impl CompassRustApp {
        fn new(config: LaunchConfig) -> Self {
            Self {
                state: DemoState::deterministic(&config.seed),
                ready_file: config.ready_file,
                screenshot_file: config.screenshot_file,
                input_file: config.input_file,
                input_ack_file: config.input_ack_file,
                semantic_snapshot_file: config.semantic_snapshot_file,
                input_observed: false,
                wrote_ready: false,
                wrote_semantic_snapshot: false,
                requested_screenshot: false,
                wrote_screenshot: false,
            }
        }

        fn observe_visual_input(&mut self) {
            if self.input_observed {
                return;
            }
            let Some(input_file) = self.input_file.as_ref() else {
                return;
            };
            if !input_file.exists() {
                return;
            }
            let input = std::fs::read_to_string(input_file).unwrap_or_else(|_| "unknown".to_owned());
            if let Some(ack_file) = self.input_ack_file.as_ref() {
                if let Err(error) = write_visual_input_ack(ack_file, input.trim()) {
                    eprintln!("could not acknowledge visual input: {error}");
                }
            }
            self.input_observed = true;
        }
    }

    impl eframe::App for CompassRustApp {
        fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
            self.observe_visual_input();

            egui::CentralPanel::default().show(ctx, |ui| {
                ui.heading("Compass Rust Desktop");
                ui.label("Visual verification target");
                ui.separator();
                ui.horizontal(|ui| {
                    ui.label("Project health");
                    ui.strong(self.state.completion_label());
                });
                ui.add_space(12.0);
                ui.label(self.state.summary_line());
                ui.add_space(12.0);
                ui.group(|ui| {
                    ui.label("Deterministic demo state");
                    ui.monospace("backend: app-core");
                    ui.monospace("frontend: eframe/egui");
                    ui.monospace("automation: xtask");
                    ui.monospace(format!(
                        "input: {}",
                        if self.input_observed {
                            "acknowledged"
                        } else if self.input_file.is_some() {
                            "waiting"
                        } else {
                            "not requested"
                        }
                    ));
                });
            });

            if !self.wrote_ready {
                write_ready_file(self.ready_file.as_ref());
                self.wrote_ready = true;
            }

            let input_ready = self.input_file.is_none() || self.input_observed;
            if input_ready && !self.wrote_semantic_snapshot {
                if let Some(path) = self.semantic_snapshot_file.as_ref() {
                    let snapshot = gui_semantic_snapshot(
                        self.state.clone(),
                        self.semantic_input_status(),
                        vec!["desktop:rendered".to_owned()],
                    );
                    match write_semantic_snapshot_file(path, &snapshot) {
                        Ok(()) => {
                            self.wrote_semantic_snapshot = true;
                        }
                        Err(error) => {
                            eprintln!("could not write semantic GUI snapshot: {error}");
                        }
                    }
                } else {
                    self.wrote_semantic_snapshot = true;
                }
            }

            for event in ctx.input(|input| input.events.clone()) {
                if let egui::Event::Screenshot { image, .. } = event {
                    if let Some(path) = self.screenshot_file.as_ref() {
                        match write_screenshot_file(path, &image) {
                            Ok(()) => {
                                self.wrote_screenshot = true;
                            }
                            Err(error) => {
                                eprintln!("could not write visual screenshot: {error}");
                            }
                        }
                    }
                }
            }

            if self.screenshot_file.is_some()
                && input_ready
                && !self.requested_screenshot
                && !self.wrote_screenshot
            {
                ctx.send_viewport_cmd(egui::ViewportCommand::Screenshot);
                self.requested_screenshot = true;
            }

            ctx.request_repaint_after(Duration::from_millis(250));
        }
    }

    impl CompassRustApp {
        fn semantic_input_status(&self) -> String {
            if self.input_observed {
                "acknowledged".to_owned()
            } else if self.input_file.is_some() {
                "waiting".to_owned()
            } else {
                "not requested".to_owned()
            }
        }
    }

    fn write_pid_file(path: Option<&PathBuf>) {
        if let Some(path) = path {
            if let Some(parent) = path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let _ = std::fs::write(path, format!("{}\\n", std::process::id()));
        }
    }

    fn write_ready_file(path: Option<&PathBuf>) {
        if let Some(path) = path {
            if let Some(parent) = path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let _ = std::fs::write(path, "ready\\n");
        }
    }

    fn write_visual_input_ack(path: &Path, input: &str) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, format!("ack:{input}\\n"))?;
        Ok(())
    }

    fn write_semantic_snapshot_file(
        path: &Path,
        snapshot: &app_core::GuiSemanticSnapshot,
    ) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, serde_json::to_string_pretty(snapshot)?)?;
        Ok(())
    }

    fn write_screenshot_file(
        path: &Path,
        screenshot: &egui::ColorImage,
    ) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut rgba = Vec::with_capacity(screenshot.pixels.len() * 4);
        for pixel in &screenshot.pixels {
            rgba.extend_from_slice(&pixel.to_array());
        }
        image::save_buffer(
            path,
            &rgba,
            screenshot.size[0] as u32,
            screenshot.size[1] as u32,
            image::ColorType::Rgba8,
        )?;
        Ok(())
    }

    """
  }

  private static func xtaskManifest() -> String {
    """
    [package]
    name = "xtask"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [dependencies]
    base64.workspace = true
    serde_json.workspace = true
    """
  }

  private static func xtaskMain() -> String {
    """
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    use std::fs::{self, File};
    use std::io;
    use std::path::{Path, PathBuf};
    use std::process::{Child, Command, Stdio};
    use std::thread;
    use std::time::{Duration, Instant};

    type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

    fn main() -> Result<()> {
        let mut raw_args = std::env::args().skip(1);
        let command = raw_args.next().unwrap_or_else(|| "verify".to_owned());
        let args: Vec<String> = raw_args.collect();
        match command.as_str() {
            "fmt" => \(xtaskCargoRunExpression(RustVerifyCommands.fmt)),
            "clippy" => \(xtaskCargoRunExpression(RustVerifyCommands.clippy)),
            "test" => \(xtaskCargoRunExpression(RustVerifyCommands.test)),
            "coverage" => \(xtaskCargoRunExpression(RustVerifyCommands.coverage)),
            "build" => \(xtaskCargoRunExpression(RustVerifyCommands.build)),
            "run" => \(xtaskCargoRunExpression(RustVerifyCommands.runDesktop)),
            "verify" => verify_all(),
            "productization-smoke" => productization_smoke(),
            "factory-smoke" => factory_smoke(args.iter().any(|arg| arg == "--emit-base64")),
            "engine-parity-check" => factory_smoke(args.iter().any(|arg| arg == "--emit-base64")),
            "visual-verify" => visual_verify(args.iter().any(|arg| arg == "--emit-base64")),
            other => Err(format!("unknown xtask command: {other}").into()),
        }
    }

    fn verify_all() -> Result<()> {
        \(xtaskCargoTryExpression(RustVerifyCommands.fmt))
        \(xtaskCargoTryExpression(RustVerifyCommands.clippy))
        \(xtaskCargoTryExpression(RustVerifyCommands.test))
        \(xtaskCargoTryExpression(RustVerifyCommands.coverage))
        \(xtaskCargoTryExpression(RustVerifyCommands.build))
        Ok(())
    }

    fn run_clippy() -> Result<()> {
        run(
            "cargo",
            &[
                "clippy",
                "--workspace",
                "--all-targets",
                "--all-features",
                "--",
                "-D",
                "warnings",
            ],
        )
    }

    fn factory_smoke(emit_base64: bool) -> Result<()> {
        verify_all()?;
        productization_smoke()?;
        visual_verify(emit_base64)?;
        Ok(())
    }

    fn productization_smoke() -> Result<()> {
        let demo = run_capture(
            "cargo",
            &["run", "-p", "app-cli", "--", "productization-experience"],
        )?;
        let demo_json: serde_json::Value = serde_json::from_slice(&demo)?;
        let initial_allowed = demo_json
            .get("allowedNextActions")
            .and_then(|value| value.as_array())
            .ok_or("productization trace is missing allowedNextActions")?;
        if initial_allowed.is_empty() {
            return Err("productization trace did not expose any initial allowed actions".into());
        }

        let input = r#"{"schemaVersion":1,"pain":{"id":"pain-reporting","summary":"Weekly reporting takes too long","impact":"Managers lose visibility"},"solution":{"id":"solution-compass","title":"Compass workflow helper","promise":"Turn scattered updates into a reviewed weekly report"},"experiment":{"id":"experiment-reporting","branchName":"productization/reporting","successSignal":"Persona completes a report draft and sees why it beats the current workflow"},"scenario":{"seed":"demo","personaSummary":"Operations lead evaluating a workflow tool","task":"Reduce weekly reporting work"},"currentWorkflow":{"summary":"Collect updates manually, paste them into a spreadsheet, and chase missing details.","frictionPoints":["manual copy paste","late follow ups"]},"alternatives":[{"id":"spreadsheet","name":"Shared spreadsheet","description":"A manual tracker with copied status updates.","switchingObjection":"The team already knows the spreadsheet."}],"actions":[{"id":"inspect_pain","params":{}},{"id":"compare_current_alternative","params":{}},{"id":"reduce_switching_objection","params":{}},{"id":"start_solution_workflow","params":{}}]}"#;
        let first = run_capture(
            "cargo",
            &[
                "run",
                "-p",
                "app-cli",
                "--",
                "productization-experience",
                "--input",
                input,
            ],
        )?;
        let second = run_capture(
            "cargo",
            &[
                "run",
                "-p",
                "app-cli",
                "--",
                "productization-experience",
                "--input",
                input,
            ],
        )?;
        if first != second {
            return Err("productization trace changed across identical invocations".into());
        }

        let trace: serde_json::Value = serde_json::from_slice(&first)?;
        let turns = trace
            .get("turns")
            .and_then(|value| value.as_array())
            .ok_or("productization trace is missing turns")?;
        if turns.len() < 4 {
            return Err("productization trace did not replay at least four actions".into());
        }
        let signals = trace
            .get("painReliefSignals")
            .and_then(|value| value.as_object())
            .ok_or("productization trace is missing painReliefSignals")?;
        if signals
            .get("currentAlternativeAddressed")
            .and_then(|value| value.as_bool())
            != Some(true)
        {
            return Err("productization trace did not address the current alternative".into());
        }
        if signals
            .get("currentAlternativeComparison")
            .and_then(|value| value.as_str())
            .unwrap_or("")
            .is_empty()
        {
            return Err(
                "productization trace did not explain the current alternative comparison".into(),
            );
        }
        println!("COMPASS_PRODUCTIZATION_SMOKE_TRACE_BYTES={}", first.len());
        Ok(())
    }

    fn visual_verify(emit_base64: bool) -> Result<()> {
        let artifact_dir = PathBuf::from(".compass/visual-verify");
        fs::create_dir_all(&artifact_dir)?;
        let ready_file = artifact_dir.join("ready.txt");
        let pid_file = artifact_dir.join("desktop.pid");
        let screenshot = artifact_dir.join("screenshot.png");
        let semantic_snapshot = artifact_dir.join("semantic-snapshot.json");
        let input_file = artifact_dir.join("input.txt");
        let input_ack_file = artifact_dir.join("input-ack.txt");
        let log_path = artifact_dir.join("desktop.log");
        remove_if_exists(&ready_file)?;
        remove_if_exists(&pid_file)?;
        remove_if_exists(&screenshot)?;
        remove_if_exists(&semantic_snapshot)?;
        remove_if_exists(&input_file)?;
        remove_if_exists(&input_ack_file)?;
        remove_if_exists(&log_path)?;

        run("cargo", &["build", "-p", "app-desktop"])?;
        let mut child = spawn_desktop(
            &ready_file,
            &pid_file,
            &screenshot,
            &semantic_snapshot,
            &input_file,
            &input_ack_file,
            &log_path,
        )?;
        let result = (|| -> Result<()> {
            wait_for_file(
                "readiness",
                &ready_file,
                Duration::from_secs(15),
                &mut child,
                &log_path,
            )?;
            thread::sleep(Duration::from_millis(500));
            send_basic_input(&input_file)?;
            wait_for_file(
                "basic input acknowledgement",
                &input_ack_file,
                Duration::from_secs(5),
                &mut child,
                &log_path,
            )?;
            wait_for_file(
                "semantic GUI snapshot",
                &semantic_snapshot,
                Duration::from_secs(5),
                &mut child,
                &log_path,
            )?;
            wait_for_file(
                "viewport screenshot",
                &screenshot,
                Duration::from_secs(10),
                &mut child,
                &log_path,
            )?;
            if !screenshot.exists() || fs::metadata(&screenshot)?.len() == 0 {
                return Err("visual verify screenshot was not captured".into());
            }
            if emit_base64 {
                let bytes = fs::read(&screenshot)?;
                println!("COMPASS_VISUAL_SCREENSHOT_BASE64_BEGIN");
                println!("{}", STANDARD.encode(bytes));
                println!("COMPASS_VISUAL_SCREENSHOT_BASE64_END");
            }
            println!("COMPASS_VISUAL_ARTIFACT_DIR={}", artifact_dir.display());
            println!(
                "COMPASS_VISUAL_SEMANTIC_SNAPSHOT_PATH={}",
                semantic_snapshot.display()
            );
            println!("COMPASS_VISUAL_SCREENSHOT_PATH={}", screenshot.display());
            println!("COMPASS_VISUAL_LOG_PATH={}", log_path.display());
            Ok(())
        })();
        terminate(&mut child, &pid_file);
        result
    }

    fn spawn_desktop(
        ready_file: &Path,
        pid_file: &Path,
        screenshot: &Path,
        semantic_snapshot: &Path,
        input_file: &Path,
        input_ack_file: &Path,
        log_path: &Path,
    ) -> Result<Child> {
        let stdout = File::create(log_path)?;
        let stderr = stdout.try_clone()?;
        let executable = std::env::current_dir()?.join("target/debug/app-desktop");
        let child = Command::new(path_str(&executable)?)
            .arg("--demo-seed")
            .arg("compass-visual-verify")
            .arg("--visual-ready-file")
            .arg(ready_file)
            .arg("--visual-pid-file")
            .arg(pid_file)
            .arg("--visual-screenshot-file")
            .arg(screenshot)
            .arg("--visual-semantic-snapshot-file")
            .arg(semantic_snapshot)
            .arg("--visual-input-file")
            .arg(input_file)
            .arg("--visual-input-ack-file")
            .arg(input_ack_file)
            .stdout(Stdio::from(stdout))
            .stderr(Stdio::from(stderr))
            .spawn()?;
        Ok(child)
    }

    fn wait_for_file(
        label: &str,
        path: &Path,
        timeout: Duration,
        child: &mut Child,
        log_path: &Path,
    ) -> Result<()> {
        let started = Instant::now();
        while started.elapsed() < timeout {
            if path.exists()
                && fs::metadata(path)
                    .map(|metadata| metadata.len() > 0)
                    .unwrap_or(false)
            {
                return Ok(());
            }
            if let Some(status) = child.try_wait()? {
                return Err(format!(
                    "desktop exited before {label}: {status}\\n{}",
                    log_tail(log_path)
                )
                .into());
            }
            thread::sleep(Duration::from_millis(150));
        }
        Err(format!(
            "desktop did not produce {label} before timeout\\n{}",
            log_tail(log_path)
        )
        .into())
    }

    fn terminate(child: &mut Child, pid_file: &Path) {
        if let Ok(raw_pid) = fs::read_to_string(pid_file) {
            if let Ok(pid) = raw_pid.trim().parse::<u32>() {
                terminate_pid(pid);
            }
        }
        if child.try_wait().ok().flatten().is_none() {
            terminate_pid(child.id());
            if child.try_wait().ok().flatten().is_none() {
                let _ = child.kill();
            }
        }
        let _ = child.wait();
    }

    fn terminate_pid(pid: u32) {
        let pid_text = pid.to_string();
        let _ = Command::new("/bin/kill")
            .arg("-TERM")
            .arg(&pid_text)
            .status();
        let started = Instant::now();
        while started.elapsed() < Duration::from_secs(2) {
            if !pid_is_running(pid) {
                return;
            }
            thread::sleep(Duration::from_millis(100));
        }
        if pid_is_running(pid) {
            let _ = Command::new("/bin/kill")
                .arg("-KILL")
                .arg(pid_text)
                .status();
        }
    }

    fn pid_is_running(pid: u32) -> bool {
        Command::new("/bin/kill")
            .arg("-0")
            .arg(pid.to_string())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|status| status.success())
            .unwrap_or(false)
    }

    fn send_basic_input(path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, "space\\n")?;
        Ok(())
    }

    fn run(program: &str, args: &[&str]) -> Result<()> {
        let status = Command::new(program).args(args).status()?;
        if status.success() {
            Ok(())
        } else {
            Err(format!("{program} {} failed with {status}", args.join(" ")).into())
        }
    }

    fn run_capture(program: &str, args: &[&str]) -> Result<Vec<u8>> {
        let output = Command::new(program).args(args).output()?;
        if output.status.success() {
            Ok(output.stdout)
        } else {
            Err(format!(
                "{program} {} failed with {}\\nstdout:\\n{}\\nstderr:\\n{}",
                args.join(" "),
                output.status,
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            )
            .into())
        }
    }

    fn remove_if_exists(path: &Path) -> io::Result<()> {
        match fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }

    fn log_tail(path: &Path) -> String {
        let Ok(contents) = fs::read_to_string(path) else {
            return "(desktop log unavailable)".to_owned();
        };
        let mut tail: Vec<&str> = contents.lines().rev().take(40).collect();
        tail.reverse();
        format!("desktop log tail:\\n{}", tail.join("\\n"))
    }

    fn path_str(path: &Path) -> Result<&str> {
        path.to_str()
            .ok_or_else(|| format!("non-utf8 path: {}", path.display()).into())
    }

    """
  }

  private static func xtaskCargoRunExpression(_ arguments: [String]) -> String {
    if arguments == RustVerifyCommands.clippy {
      return "run_clippy()"
    }
    return "run(\"cargo\", &\(rustStringArrayLiteral(arguments)))"
  }

  private static func xtaskCargoTryExpression(_ arguments: [String]) -> String {
    "\(xtaskCargoRunExpression(arguments))?;"
  }

  private static func rustStringArrayLiteral(_ values: [String]) -> String {
    "[" + values.map { "\"\(rustStringLiteralContent($0))\"" }.joined(separator: ", ") + "]"
  }
}
