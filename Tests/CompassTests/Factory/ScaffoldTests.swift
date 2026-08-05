import Foundation
import Testing

@testable import Compass
@testable import CompassCore

@Suite("Rust scaffold")
struct ScaffoldTests {
  @Test
  func rustScaffoldHasCargoWorkspaceAndCrates() throws {
    let files = RustProjectScaffold.files(
      options: .init(projectName: "My Factory App")
    )
    let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.contents) })

    #expect(byPath.keys.contains("Cargo.toml"))
    #expect(byPath.keys.contains("rust-toolchain.toml"))
    #expect(byPath.keys.contains("crates/core/Cargo.toml"))
    #expect(byPath.keys.contains("crates/cli/Cargo.toml"))
    #expect(byPath.keys.contains("crates/core/src/lib.rs"))
    #expect(byPath.keys.contains("crates/cli/src/main.rs"))
    #expect(byPath.keys.contains("crates/cli/tests/cli.rs"))
    #expect(byPath.keys.contains("crates/ui/Cargo.toml"))
    #expect(byPath.keys.contains("crates/ui/src/lib.rs"))
    #expect(byPath.keys.contains("crates/ffi/Cargo.toml"))
    #expect(byPath.keys.contains("apps/macos/Package.swift"))
    #expect(byPath.keys.contains("apps/macos/Sources/AppFFI/Placeholder.swift"))
    #expect(byPath.keys.contains("apps/macos/Sources/app_ffiFFI/shim.c"))
    #expect(byPath.keys.contains("apps/macos/Sources/app_ffiFFI/include/.gitkeep"))
    #expect(byPath.keys.contains("apps/macos/Tests/GeneratedAppTests/UiFFITests.swift"))
    #expect(byPath.keys.contains("apps/macos/Info.plist"))
    #expect(byPath.keys.contains("scripts/generate-bindings.sh"))
    #expect(byPath.keys.contains("scripts/bundle-macos.sh"))
    #expect(byPath.keys.contains("scripts/verify-macos.sh"))
    #expect(byPath.keys.contains("scripts/macos-ui-smoke.sh"))
    #expect(byPath.keys.contains("scripts/macos-ax-smoke.swift"))

    let app = try #require(byPath["apps/macos/Sources/GeneratedApp/GeneratedApp.swift"])
    #expect(app.contains("import AppFFI"))
    #expect(app.contains("uiInitialSnapshot"))
    #expect(app.contains("greeting.label"))
    #expect(!byPath.keys.contains("apps/macos/Sources/GeneratedApp/GreetingBridge.swift"))

    let ui = try #require(byPath["crates/ui/src/lib.rs"])
    #expect(ui.contains("struct ViewState"))
    #expect(ui.contains("struct Simulator"))
    #expect(ui.contains("fn check_guardrails"))
    #expect(ui.contains("greeting.label"))

    let ffi = try #require(byPath["crates/ffi/src/lib.rs"])
    #expect(ffi.contains("uniffi::Record"))
    #expect(ffi.contains("ui_initial_snapshot"))
    #expect(ffi.contains("app_ui::"))

    let verify = try #require(byPath["scripts/verify-macos.sh"])
    #expect(verify.contains("swift test"))
    #expect(verify.contains("swift-format"))
    #expect(verify.contains("macos-ui-smoke.sh"))
    #expect(verify.contains("crates/ui"))

    let uiSmoke = try #require(byPath["scripts/macos-ui-smoke.sh"])
    #expect(uiSmoke.contains("COMPASS_MACOS_UI_FIDELITY"))
    #expect(uiSmoke.contains("launchctl asuser"))
    #expect(uiSmoke.contains("screencapture"))
    #expect(
      uiSmoke.contains("greeting.label")
        || byPath["scripts/macos-ax-smoke.swift"]!.contains("greeting.label"))

    let axSmoke = try #require(byPath["scripts/macos-ax-smoke.swift"])
    #expect(axSmoke.contains("greeting.label"))
    #expect(axSmoke.contains("hello, world!"))
    #expect(axSmoke.contains("crates/ui"))

    let workspace = try #require(byPath["Cargo.toml"])
    #expect(workspace.contains("crates/core"))
    #expect(workspace.contains("crates/cli"))
    #expect(workspace.contains("crates/ui"))
    #expect(workspace.contains("crates/ffi"))
    #expect(workspace.contains("app-ui"))

    let readme = try #require(byPath["README.md"])
    #expect(readme.contains("cargo llvm-cov"))
    #expect(readme.contains("verify-macos"))
    #expect(readme.contains("COMPASS_MACOS_UI_FIDELITY"))
    #expect(readme.contains("crates/ui"))
  }

  @Test
  func rustScaffoldCliOnlyOmitsMacOS() throws {
    let files = RustProjectScaffold.files(
      options: .init(projectName: "CLI Only", products: [.cli])
    )
    let paths = Set(files.map(\.path))
    #expect(paths.contains("crates/core/Cargo.toml"))
    #expect(paths.contains("crates/cli/Cargo.toml"))
    #expect(!paths.contains("crates/ui/Cargo.toml"))
    #expect(!paths.contains("crates/ffi/Cargo.toml"))
    #expect(!paths.contains("apps/macos/Package.swift"))
    #expect(!paths.contains("scripts/verify-macos.sh"))
  }

  @Test
  func rustScaffoldMacOSOnlyOmitsCLI() throws {
    let files = RustProjectScaffold.files(
      options: .init(projectName: "Mac Only", products: [.macos])
    )
    let paths = Set(files.map(\.path))
    #expect(paths.contains("crates/core/Cargo.toml"))
    #expect(paths.contains("crates/ui/Cargo.toml"))
    #expect(paths.contains("crates/ffi/Cargo.toml"))
    #expect(paths.contains("apps/macos/Package.swift"))
    #expect(!paths.contains("crates/cli/Cargo.toml"))
  }

  @Test
  func rustScaffoldDetectsGeneratedWorkspace() throws {
    let tempURL = FileManager.default.temporaryDirectory
      .appending(path: "CompassRustScaffoldTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: tempURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try RustProjectScaffold.write(
      to: tempURL,
      options: .init(projectName: "Detected App", products: [.cli])
    )

    #expect(RustProjectScaffold.isGeneratedWorkspace(at: tempURL))
    #expect(RepositoryManifestHint.cargoToml.language == .rust)
  }

  @Test
  func fidelityEnvDefaultsOffAndPrefixesVerifyCommand() {
    #expect(!MacOSUISmokeSupport.isFidelityEnabled(environment: [:]))
    #expect(!MacOSUISmokeSupport.isFidelityEnabled(environment: ["COMPASS_MACOS_UI_FIDELITY": "0"]))
    #expect(MacOSUISmokeSupport.isFidelityEnabled(environment: ["COMPASS_MACOS_UI_FIDELITY": "1"]))
    let prefixed = MacOSUISmokeSupport.verifyCommand(
      environment: ["COMPASS_MACOS_UI_FIDELITY": "true"]
    )
    #expect(prefixed.hasPrefix("COMPASS_MACOS_UI_FIDELITY=1 "))
    #expect(prefixed.contains(GeneratedProjectQuality.macosVerifyCommand))
    #expect(
      MacOSUISmokeSupport.verifyCommand(environment: [:])
        == GeneratedProjectQuality.macosVerifyCommand
    )
  }

  @Test
  func generatedVerifyGateAcceptsCompassStandardVerify() {
    let standardVerify =
      GeneratedProjectQuality.standardVerifyCommand
    #expect(
      GeneratedVerifyValidator.coverageViolation(verify: standardVerify) == nil
    )
    #expect(
      GeneratedVerifyValidator.coverageViolation(
        verify: "cargo llvm-cov --workspace --summary-only")
        == nil
    )
    #expect(
      GeneratedVerifyValidator.coverageViolation(verify: "cargo test --workspace") == nil
    )

    let violation = GeneratedVerifyValidator.coverageViolation(verify: "echo ok")
    #expect(violation != nil)
    #expect(violation?.contains("llvm-cov") == true)
  }
}
