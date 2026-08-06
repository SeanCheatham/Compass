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
    #expect(byPath.keys.contains("apps/macos/Sources/MyFactoryApp/MyFactoryApp.swift"))
    #expect(byPath.keys.contains("apps/macos/Sources/FFIChecks/main.swift"))
    #expect(!byPath.keys.contains("apps/macos/Tests/GeneratedAppTests/UiFFITests.swift"))
    #expect(byPath.keys.contains("apps/macos/Info.plist"))
    #expect(byPath.keys.contains("scripts/generate-bindings.sh"))
    #expect(byPath.keys.contains("scripts/bundle-macos.sh"))
    #expect(byPath.keys.contains("scripts/verify-macos.sh"))
    #expect(byPath.keys.contains("scripts/macos-ui-smoke.sh"))
    #expect(byPath.keys.contains("scripts/macos-ax-smoke.swift"))

    let app = try #require(byPath["apps/macos/Sources/MyFactoryApp/MyFactoryApp.swift"])
    #expect(app.contains("import AppFFI"))
    #expect(app.contains("uiInitialSnapshot"))
    #expect(app.contains("greeting.label"))
    #expect(app.contains("struct MyFactoryApp"))
    #expect(app.contains("WindowGroup(\"My Factory App\")"))
    #expect(!byPath.keys.contains("apps/macos/Sources/GeneratedApp/GreetingBridge.swift"))

    let package = try #require(byPath["apps/macos/Package.swift"])
    #expect(package.contains("name: \"MyFactoryApp\""))
    #expect(package.contains("FFIChecks"))
    #expect(package.contains("Context.packageDirectory"))
    #expect(!package.contains("GeneratedAppTests"))
    #expect(!package.contains("import XCTest"))
    #expect(!package.contains(".testTarget("))

    let ffiChecks = try #require(byPath["apps/macos/Sources/FFIChecks/main.swift"])
    #expect(ffiChecks.contains("FFIChecks ok"))
    #expect(!ffiChecks.contains("import XCTest"))

    let info = try #require(byPath["apps/macos/Info.plist"])
    #expect(info.contains("com.compass.generated.myfactoryapp"))
    #expect(info.contains("MyFactoryApp"))

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
    #expect(verify.contains("swift run"))
    #expect(verify.contains("FFIChecks"))
    #expect(verify.contains("not `swift test`") || verify.contains("not swift test"))
    #expect(!verify.contains("\nswift test\n") && !verify.contains("swift test\n"))
    #expect(verify.contains("swift-format"))
    #expect(verify.contains("macos-ui-smoke.sh"))
    #expect(verify.contains("crates/ui"))
    #expect(verify.contains("Sources/MyFactoryApp"))

    let uiSmoke = try #require(byPath["scripts/macos-ui-smoke.sh"])
    #expect(uiSmoke.contains("COMPASS_MACOS_UI_FIDELITY"))
    #expect(uiSmoke.contains("launchctl asuser"))
    #expect(uiSmoke.contains("screencapture"))
    #expect(uiSmoke.contains("com.compass.generated.myfactoryapp"))
    #expect(
      uiSmoke.contains("greeting.label")
        || byPath["scripts/macos-ax-smoke.swift"]!.contains("greeting.label"))

    let axSmoke = try #require(byPath["scripts/macos-ax-smoke.swift"])
    #expect(axSmoke.contains("greeting.label"))
    #expect(axSmoke.contains("hello, world!"))
    #expect(axSmoke.contains("crates/ui"))
    #expect(axSmoke.contains("com.compass.generated.myfactoryapp"))

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
    #expect(readme.contains("Current status"))
  }

  @Test
  func rustScaffoldMacOSNamingSanitizesIdentifiers() {
    let naming = RustProjectScaffold.MacOSNaming(projectName: "CompassRustApp5")
    #expect(naming.moduleName == "CompassRustApp5")
    #expect(naming.bundleIdentifier == "com.compass.generated.compassrustapp5")
    #expect(RustProjectScaffold.MacOSNaming.swiftTypeName(from: "my factory app") == "MyFactoryApp")
    #expect(RustProjectScaffold.MacOSNaming.swiftTypeName(from: "cli-fixture") == "CliFixture")
    #expect(RustProjectScaffold.MacOSNaming.swiftTypeName(from: "99 bottles") == "App99Bottles")
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
  func rustScaffoldServerOnlyIncludesHTTPHarness() throws {
    let files = RustProjectScaffold.files(
      options: .init(projectName: "API Only", products: [.server])
    )
    let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.contents) })
    #expect(byPath.keys.contains("crates/core/Cargo.toml"))
    #expect(byPath.keys.contains("crates/server/Cargo.toml"))
    #expect(byPath.keys.contains("crates/server/src/lib.rs"))
    #expect(byPath.keys.contains("crates/server/src/main.rs"))
    #expect(byPath.keys.contains("crates/server/tests/http.rs"))
    #expect(!byPath.keys.contains("crates/cli/Cargo.toml"))
    #expect(!byPath.keys.contains("apps/macos/Package.swift"))

    let workspace = try #require(byPath["Cargo.toml"])
    #expect(workspace.contains("crates/server"))
    #expect(workspace.contains("axum"))
    #expect(workspace.contains("tokio"))

    let httpTest = try #require(byPath["crates/server/tests/http.rs"])
    #expect(httpTest.contains("oneshot"))
    #expect(httpTest.contains("/status"))

    let cliFiles = RustProjectScaffold.files(
      options: .init(projectName: "CLI Harness", products: [.cli])
    )
    let cliTest = try #require(
      Dictionary(uniqueKeysWithValues: cliFiles.map { ($0.path, $0.contents) })[
        "crates/cli/tests/cli.rs"]
    )
    #expect(cliTest.contains("CARGO_BIN_EXE_app-cli"))
    #expect(cliTest.contains("status_prints_greeting_golden"))
    #expect(cliTest.contains("unknown_command_exits_2"))
  }

  @Test
  func fidelityCadenceRunsEveryNthShip() {
    #expect(
      !MacOSFidelityCadence.shouldEnableFidelity(
        successfulShipCount: 1, cadence: 5, force: false, environment: [:]))
    #expect(
      MacOSFidelityCadence.shouldEnableFidelity(
        successfulShipCount: 5, cadence: 5, force: false, environment: [:]))
    #expect(
      MacOSFidelityCadence.shouldEnableFidelity(
        successfulShipCount: 10, cadence: 5, force: false, environment: [:]))
    #expect(
      MacOSFidelityCadence.shouldEnableFidelity(
        successfulShipCount: 3, cadence: 5, force: true, environment: [:]))
    #expect(
      MacOSFidelityCadence.shouldEnableFidelity(
        successfulShipCount: 2, cadence: 5, force: false,
        environment: ["COMPASS_MACOS_UI_FIDELITY": "1"]))
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
