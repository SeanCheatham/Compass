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
      ScaffoldFile(path: "Cargo.toml", contents: workspaceManifest()),
      ScaffoldFile(path: "rust-toolchain.toml", contents: rustToolchain()),
      ScaffoldFile(path: "README.md", contents: readme(projectName: projectName)),
      ScaffoldFile(path: "schemas/demo-state.schema.json", contents: demoStateSchema()),
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

    ## Standard Commands

    - Format: `\(RustVerifyCommands.cargo(RustVerifyCommands.fmt))`
    - Lint: `\(RustVerifyCommands.cargo(RustVerifyCommands.clippy))`
    - Test: `\(RustVerifyCommands.cargo(RustVerifyCommands.test))`
    - Coverage: `\(RustVerifyCommands.cargo(RustVerifyCommands.coverage))`
    - Build: `\(RustVerifyCommands.cargo(RustVerifyCommands.build))`
    - Run CLI: `\(RustVerifyCommands.cargo(["run", "-p", "app-cli", "--", "status"]))`
    - Run desktop: `\(RustVerifyCommands.cargo(RustVerifyCommands.runDesktop))`
    - Verify all: `cargo run -p xtask -- verify`
    - Engine parity check: `\(RustVerifyCommands.cargo(RustVerifyCommands.engineParityCheck))`
    - Visual verify: `\(RustProjectScaffold.visualVerifyCommand)`

    The desktop app uses deterministic demo state and stable window labels so Compass can
    build it in the Shared VM, launch it in the guest, wait for readiness, send a
    platform-neutral visual input request, capture a Rust-rendered viewport artifact,
    and terminate it cleanly.
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

    """
  }

  private static func appCoreTests() -> String {
    """
    use app_core::DemoState;

    #[test]
    fn deterministic_state_has_stable_labels() {
        let state = DemoState::deterministic("compass-demo");

        assert_eq!(state.headline, "Rust workspace ready");
        assert!(state.completion_label().contains("checks ready"));
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
    use app_core::{demo_state_schema, DemoState};

    fn main() -> Result<(), Box<dyn std::error::Error>> {
        let mut args = std::env::args().skip(1);
        match args.next().as_deref() {
            None | Some("status") => {
                println!("{}", DemoState::deterministic("cli").summary_line());
            }
            Some("schema") => {
                println!("{}", serde_json::to_string_pretty(&demo_state_schema())?);
            }
            Some(other) => {
                eprintln!("unknown command: {other}");
                eprintln!("usage: app-cli [status|schema]");
                std::process::exit(2);
            }
        }
        Ok(())
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
    """
  }

  private static func appDesktopMain(windowTitle: String) -> String {
    """
    use app_core::DemoState;
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
        input_observed: bool,
        wrote_ready: bool,
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
                input_observed: false,
                wrote_ready: false,
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

            let input_ready = self.input_file.is_none() || self.input_observed;
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
            "engine-parity-check" => engine_parity_check(),
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

    fn engine_parity_check() -> Result<()> {
        verify_all()?;
        visual_verify(false)?;
        Ok(())
    }

    fn visual_verify(emit_base64: bool) -> Result<()> {
        let artifact_dir = PathBuf::from(".compass/visual-verify");
        fs::create_dir_all(&artifact_dir)?;
        let ready_file = artifact_dir.join("ready.txt");
        let pid_file = artifact_dir.join("desktop.pid");
        let screenshot = artifact_dir.join("screenshot.png");
        let input_file = artifact_dir.join("input.txt");
        let input_ack_file = artifact_dir.join("input-ack.txt");
        let log_path = artifact_dir.join("desktop.log");
        remove_if_exists(&ready_file)?;
        remove_if_exists(&pid_file)?;
        remove_if_exists(&screenshot)?;
        remove_if_exists(&input_file)?;
        remove_if_exists(&input_ack_file)?;
        remove_if_exists(&log_path)?;

        run("cargo", &["build", "-p", "app-desktop"])?;
        let mut child = spawn_desktop(
            &ready_file,
            &pid_file,
            &screenshot,
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
    "run(\"cargo\", &\(rustStringArrayLiteral(arguments)))"
  }

  private static func xtaskCargoTryExpression(_ arguments: [String]) -> String {
    "\(xtaskCargoRunExpression(arguments))?;"
  }

  private static func rustStringArrayLiteral(_ values: [String]) -> String {
    "[" + values.map { "\"\(rustStringLiteralContent($0))\"" }.joined(separator: ", ") + "]"
  }
}
