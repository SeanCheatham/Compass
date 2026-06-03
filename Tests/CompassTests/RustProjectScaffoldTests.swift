import Foundation
import Testing

@testable import Compass

struct RustProjectScaffoldTests {
  @Test func scaffoldUsesBlessedCargoWorkspaceShape() throws {
    let files = RustProjectScaffold.files()
    let paths = Set(files.map(\.path))

    try #require(paths.contains("Cargo.toml"))
    try #require(paths.contains("rust-toolchain.toml"))
    try #require(paths.contains("crates/app-core/src/lib.rs"))
    try #require(paths.contains("crates/app-cli/src/main.rs"))
    try #require(paths.contains("crates/app-desktop/src/main.rs"))
    try #require(paths.contains("xtask/src/main.rs"))
    try #require(paths.contains("schemas/demo-state.schema.json"))
    try #require(!paths.contains("Package.swift"))
    try #require(!paths.contains("package.json"))
  }

  @Test func scaffoldDocumentsStandardRustCommandsAndDesktopStack() throws {
    let readme = try #require(
      RustProjectScaffold.files().first { $0.path == "README.md" }?.contents)

    try #require(readme.contains("Compass itself remains a native Swift/macOS app"))
    try #require(readme.contains("generated output lives here as Rust"))
    try #require(readme.contains("eframe"))
    try #require(readme.contains("egui"))
    try #require(readme.contains("cargo fmt --all --check"))
    try #require(readme.contains("cargo clippy --workspace --all-targets --all-features"))
    try #require(readme.contains("cargo test --workspace --all-features"))
    try #require(readme.contains("cargo llvm-cov --summary-only"))
    try #require(readme.contains("cargo build --workspace"))
    try #require(readme.contains(RustProjectScaffold.visualVerifyCommand))
  }

  @Test func desktopTemplateHasStableVisualVerificationLabels() throws {
    let desktop = try #require(
      RustProjectScaffold.files().first { $0.path == "crates/app-desktop/src/main.rs" }?.contents)

    try #require(desktop.contains("Compass Rust Desktop"))
    try #require(desktop.contains("Visual verification target"))
    try #require(desktop.contains("Project health"))
    try #require(desktop.contains("--visual-ready-file"))
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

    try #require(xtask.contains("cargo"))
    try #require(xtask.contains("build"))
    try #require(
      xtask.contains("\"coverage\" => run(\"cargo\", &[\"llvm-cov\", \"--summary-only\"])"))
    try #require(xtask.contains("run(\"cargo\", &[\"llvm-cov\", \"--summary-only\"])?"))
    try #require(xtask.contains("spawn_desktop"))
    try #require(xtask.contains("wait_for_ready"))
    try #require(xtask.contains("screencapture"))
    try #require(xtask.contains("osascript"))
    try #require(xtask.contains("terminate"))
    try #require(xtask.contains(RustDesktopVisualVerification.screenshotBeginMarker))
    try #require(xtask.contains(RustDesktopVisualVerification.screenshotEndMarker))
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
}
