import Foundation

public enum RustProjectScaffold {
  public struct Options: Equatable, Sendable {
    public var projectName: String
    public var products: [GeneratedProduct]

    public init(
      projectName: String,
      products: [GeneratedProduct] = GeneratedProducts.default
    ) {
      self.projectName = Self.displayName(projectName)
      self.products = GeneratedProducts.normalize(products)
    }

    private static func displayName(_ raw: String) -> String {
      let cleaned =
        raw
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return cleaned.isEmpty ? "Compass App" : String(cleaned.prefix(80))
    }
  }

  public struct ScaffoldFile: Equatable, Sendable {
    public var path: String
    public var contents: String
  }

  public static func files(options: Options) -> [ScaffoldFile] {
    let name = options.projectName
    let products = options.products
    let hasCLI = GeneratedProducts.contains(products, .cli)
    let hasMacOS = GeneratedProducts.contains(products, .macos)

    var files: [ScaffoldFile] = [
      ScaffoldFile(path: ".gitignore", contents: gitignore(hasMacOS: hasMacOS)),
      ScaffoldFile(path: "Cargo.toml", contents: workspaceManifest(hasCLI: hasCLI, hasMacOS: hasMacOS)),
      ScaffoldFile(path: "rust-toolchain.toml", contents: rustToolchain),
      ScaffoldFile(
        path: "README.md",
        contents: readme(projectName: name, hasCLI: hasCLI, hasMacOS: hasMacOS)
      ),
      ScaffoldFile(path: "crates/core/Cargo.toml", contents: coreManifest),
      ScaffoldFile(path: "crates/core/src/lib.rs", contents: coreLib),
    ]

    if hasCLI {
      files.append(contentsOf: [
        ScaffoldFile(path: "crates/cli/Cargo.toml", contents: cliManifest),
        ScaffoldFile(path: "crates/cli/src/main.rs", contents: cliMain),
        ScaffoldFile(path: "crates/cli/tests/cli.rs", contents: cliSmokeTest),
      ])
    }

    if hasMacOS {
      files.append(contentsOf: [
        ScaffoldFile(path: ".swift-format", contents: swiftFormatConfig),
        ScaffoldFile(path: "crates/ffi/Cargo.toml", contents: ffiManifest),
        ScaffoldFile(path: "crates/ffi/src/lib.rs", contents: ffiLib),
        ScaffoldFile(path: "crates/ffi/src/bin/uniffi-bindgen.rs", contents: ffiBindgenMain),
        ScaffoldFile(path: "apps/macos/Package.swift", contents: macosPackageSwift),
        ScaffoldFile(
          path: "apps/macos/Sources/GeneratedApp/GeneratedApp.swift",
          contents: macosAppSwift(projectName: name)
        ),
        ScaffoldFile(
          path: "apps/macos/Sources/AppFFI/Placeholder.swift",
          contents: macosBindingsPlaceholder
        ),
        ScaffoldFile(path: "apps/macos/Sources/app_ffiFFI/shim.c", contents: macosFFIShim),
        ScaffoldFile(
          path: "apps/macos/Sources/app_ffiFFI/include/.gitkeep",
          contents: ""
        ),
        ScaffoldFile(
          path: "apps/macos/Tests/GeneratedAppTests/GreetingFFITests.swift",
          contents: macosFFITests
        ),
        ScaffoldFile(path: "apps/macos/Info.plist", contents: macosInfoPlist),
        ScaffoldFile(path: "scripts/generate-bindings.sh", contents: generateBindingsScript),
        ScaffoldFile(path: "scripts/bundle-macos.sh", contents: bundleMacOSScript),
        ScaffoldFile(path: "scripts/macos-ax-smoke.swift", contents: macosAXSmokeSwift),
        ScaffoldFile(path: "scripts/macos-ui-smoke.sh", contents: macosUISmokeScript),
        ScaffoldFile(path: "scripts/verify-macos.sh", contents: verifyMacOSScript),
      ])
    }

    return files
  }

  public static func write(to url: URL, options: Options) throws {
    if let error = GeneratedProducts.validate(options.products) {
      throw GeneratedProductError.invalid(error)
    }
    let fm = FileManager.default
    try fm.createDirectory(at: url, withIntermediateDirectories: true)
    for file in files(options: options) {
      let destination = url.appending(path: file.path)
      try fm.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
      )
      let contents =
        file.contents.isEmpty || file.contents.hasSuffix("\n")
        ? file.contents
        : file.contents + "\n"
      try contents.write(to: destination, atomically: true, encoding: .utf8)
      if file.path.hasSuffix(".sh") {
        try fm.setAttributes(
          [.posixPermissions: 0o755],
          ofItemAtPath: destination.path
        )
      }
    }
  }

  public static func isGeneratedWorkspace(at url: URL) -> Bool {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.appending(path: "Cargo.toml").path),
      fm.fileExists(atPath: url.appending(path: "crates/core/Cargo.toml").path)
    else {
      return false
    }
    let hasCLI = fm.fileExists(atPath: url.appending(path: "crates/cli/Cargo.toml").path)
    let hasMacOS =
      fm.fileExists(atPath: url.appending(path: "apps/macos/Package.swift").path)
      || fm.fileExists(atPath: url.appending(path: "crates/ffi/Cargo.toml").path)
    return hasCLI || hasMacOS
  }

  private static func gitignore(hasMacOS: Bool) -> String {
    var lines = """
      /target/
      /mutants.out*/
      .DS_Store
      *.log
      """
    if hasMacOS {
      lines += """

        /apps/macos/.build/
        /apps/macos/dist/
        /apps/macos/Sources/AppFFI/app_ffi.swift
        /apps/macos/Sources/app_ffiFFI/include/app_ffiFFI.h
        """
    }
    return lines
  }

  private static func workspaceManifest(hasCLI: Bool, hasMacOS: Bool) -> String {
    var members = ["\"crates/core\""]
    if hasCLI { members.append("\"crates/cli\"") }
    if hasMacOS { members.append("\"crates/ffi\"") }
    var dependencyLines = [
      "app-core = { path = \"crates/core\" }"
    ]
    if hasMacOS {
      dependencyLines.append("uniffi = { version = \"0.28.3\", features = [\"cli\"] }")
    }
    return """
      [workspace]
      resolver = "2"
      members = [
        \(members.joined(separator: ",\n  ")),
      ]

      [workspace.package]
      edition = "2021"
      license = "MIT"
      version = "0.1.0"

      [workspace.dependencies]
      \(dependencyLines.joined(separator: "\n"))
      """
  }

  private static let rustToolchain = """
    [toolchain]
    channel = "stable"
    components = ["rustfmt", "clippy"]
    """

  private static func readme(projectName: String, hasCLI: Bool, hasMacOS: Bool) -> String {
    var layout: [String] = [
      "- `crates/core`: shared Rust domain logic (required)"
    ]
    if hasCLI {
      layout.append("- `crates/cli`: command-line product over `core`")
    }
    if hasMacOS {
      layout.append("- `crates/ffi`: UniFFI exports over `core`")
      layout.append("- `apps/macos`: thin SwiftUI shell (no domain logic) over the UniFFI bindings")
    }
    var commands = """
      - Format: `cargo fmt --all --check`
      - Lint: `cargo clippy --workspace --all-targets --all-features -- -D warnings`
      - Test: `cargo test --workspace`
      - Coverage: `cargo llvm-cov --workspace --summary-only`
      - Verify (Rust): `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace`
      """
    if hasCLI {
      commands += """
        - Run CLI: `cargo run -p app-cli -- status`
        """
    }
    if hasMacOS {
      commands += """
        - Bindings (macOS): `bash scripts/generate-bindings.sh`
        - Verify (macOS, host/VM): `bash scripts/verify-macos.sh`
        - Bundle (macOS): `bash scripts/bundle-macos.sh`
        """
    }
    let products = [
      hasCLI ? "cli" : nil,
      hasMacOS ? "macos" : nil,
    ].compactMap { $0 }.joined(separator: "+")
    return """
      # \(projectName)

      A Compass-generated project with required Rust `crates/core` and products: \(products).

      Domain logic lives in `crates/core` only. CLI and macOS are adapters.

      ## Layout

      \(layout.joined(separator: "\n"))

      ## Commands

      \(commands)
      """
  }

  private static let coreManifest = """
    [package]
    name = "app-core"
    edition.workspace = true
    license.workspace = true
    version.workspace = true
    """

  private static let coreLib = """
    /// Minimal greeting used by CLI and macOS smoke paths.
    pub fn greeting(name: &str) -> String {
        format!("hello, {name}")
    }

    /// Input for a personalized greeting, shared by all product shells.
    pub struct GreetingRequest {
        pub name: String,
        pub excited: bool,
    }

    /// Errors the greeting flow can surface to product shells.
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum GreetingError {
        EmptyName,
    }

    impl std::fmt::Display for GreetingError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                Self::EmptyName => write!(f, "name must not be empty"),
            }
        }
    }

    impl std::error::Error for GreetingError {}

    /// Greeting variant that validates input and honors tone.
    pub fn personalized_greeting(request: &GreetingRequest) -> Result<String, GreetingError> {
        let name = request.name.trim();
        if name.is_empty() {
            return Err(GreetingError::EmptyName);
        }
        let base = greeting(name);
        Ok(if request.excited {
            format!("{base}!")
        } else {
            base
        })
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn greeting_includes_name() {
            assert_eq!(greeting("compass"), "hello, compass");
        }

        #[test]
        fn personalized_greeting_marks_excitement() {
            let request = GreetingRequest {
                name: "world".into(),
                excited: true,
            };
            assert_eq!(personalized_greeting(&request).unwrap(), "hello, world!");
        }

        #[test]
        fn personalized_greeting_rejects_blank_names() {
            let request = GreetingRequest {
                name: "  ".into(),
                excited: false,
            };
            assert_eq!(
                personalized_greeting(&request),
                Err(GreetingError::EmptyName)
            );
        }
    }
    """

  private static let cliManifest = """
    [package]
    name = "app-cli"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [dependencies]
    app-core.workspace = true
    """

  private static let cliMain = """
    use app_core::greeting;

    fn main() {
        let mut args = std::env::args().skip(1);
        match args.next().as_deref() {
            None | Some("status") => {
                println!("{}", greeting("world"));
            }
            Some(other) => {
                eprintln!("unknown command: {other}");
                eprintln!("usage: app-cli [status]");
                std::process::exit(2);
            }
        }
    }
    """

  private static let cliSmokeTest = """
    use std::process::Command;

    #[test]
    fn status_prints_greeting() {
        let output = Command::new(env!("CARGO_BIN_EXE_app-cli"))
            .arg("status")
            .output()
            .expect("run app-cli");
        assert!(output.status.success());
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(stdout.contains("hello, world"), "stdout was: {stdout}");
    }
    """

  private static let ffiManifest = """
    [package]
    name = "app-ffi"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [lib]
    name = "app_ffi"
    crate-type = ["cdylib", "staticlib", "lib"]

    [dependencies]
    app-core.workspace = true
    uniffi = { workspace = true }

    [[bin]]
    name = "uniffi-bindgen"
    path = "src/bin/uniffi-bindgen.rs"
    """

  private static let ffiLib = """
    uniffi::setup_scaffolding!();

    /// UniFFI export mirroring `app_core::greeting` for the macOS shell.
    #[uniffi::export]
    pub fn greeting(name: String) -> String {
        app_core::greeting(&name)
    }

    /// Record crossing the FFI boundary as a Swift value type.
    #[derive(uniffi::Record)]
    pub struct GreetingRequest {
        pub name: String,
        pub excited: bool,
    }

    /// Error surfaced to Swift as a thrown `GreetingError`.
    #[derive(Debug, uniffi::Error)]
    pub enum GreetingError {
        EmptyName,
    }

    impl std::fmt::Display for GreetingError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                Self::EmptyName => write!(f, "name must not be empty"),
            }
        }
    }

    impl std::error::Error for GreetingError {}

    impl From<app_core::GreetingError> for GreetingError {
        fn from(_: app_core::GreetingError) -> Self {
            Self::EmptyName
        }
    }

    /// Validated greeting that exercises records, errors, and `Result` over FFI.
    #[uniffi::export]
    pub fn personalized_greeting(request: GreetingRequest) -> Result<String, GreetingError> {
        let request = app_core::GreetingRequest {
            name: request.name,
            excited: request.excited,
        };
        Ok(app_core::personalized_greeting(&request)?)
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn greeting_matches_core() {
            assert_eq!(greeting("compass".into()), "hello, compass");
        }

        #[test]
        fn personalized_greeting_matches_core() {
            let request = GreetingRequest {
                name: "world".into(),
                excited: true,
            };
            assert_eq!(personalized_greeting(request).unwrap(), "hello, world!");
        }

        #[test]
        fn personalized_greeting_rejects_blank_names() {
            let request = GreetingRequest {
                name: " ".into(),
                excited: false,
            };
            assert!(matches!(
                personalized_greeting(request),
                Err(GreetingError::EmptyName)
            ));
        }
    }
    """

  private static let ffiBindgenMain = """
    fn main() {
        uniffi::uniffi_bindgen_main()
    }
    """

  private static let macosPackageSwift = """
    // swift-tools-version: 5.9
    import PackageDescription

    let package = Package(
        name: "GeneratedApp",
        platforms: [.macOS(.v14)],
        targets: [
            .target(
                name: "app_ffiFFI",
                path: "Sources/app_ffiFFI",
                publicHeadersPath: "include"
            ),
            .target(
                name: "AppFFI",
                dependencies: ["app_ffiFFI"],
                path: "Sources/AppFFI",
                linkerSettings: [
                    .unsafeFlags(["../../target/release/libapp_ffi.a"])
                ]
            ),
            .executableTarget(
                name: "GeneratedApp",
                dependencies: ["AppFFI"],
                path: "Sources/GeneratedApp"
            ),
            .testTarget(
                name: "GeneratedAppTests",
                dependencies: ["AppFFI"],
                path: "Tests/GeneratedAppTests"
            ),
        ]
    )
    """

  private static func macosAppSwift(projectName: String) -> String {
    """
    import AppFFI
    import SwiftUI

    @main
    struct GeneratedApp: App {
      var body: some Scene {
        WindowGroup("\(projectName)") {
          ContentView()
        }
      }
    }

    struct ContentView: View {
      private let message: String

      init() {
        let request = GreetingRequest(name: "world", excited: true)
        message = (try? personalizedGreeting(request: request)) ?? greeting(name: "world")
      }

      var body: some View {
        VStack(spacing: 12) {
          Text(message)
            .accessibilityIdentifier("greeting.label")
          Text("Core logic lives in crates/core; this shell is SwiftUI only.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("greeting.caption")
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 180)
      }
    }
    """
  }

  private static let macosBindingsPlaceholder = """
    // Placeholder so the AppFFI target exists on a fresh checkout.
    // `scripts/generate-bindings.sh` emits the real UniFFI-generated
    // `app_ffi.swift` into this directory (gitignored).
    """

  private static let macosFFIShim = """
    /* SwiftPM requires at least one source file per C target.
     * The real declarations come from the UniFFI-generated
     * `include/app_ffiFFI.h`, emitted by scripts/generate-bindings.sh. */
    """

  private static let macosFFITests = """
    import AppFFI
    import XCTest

    final class GreetingFFITests: XCTestCase {
      func testGreetingCrossesFFIBoundary() {
        XCTAssertEqual(greeting(name: "compass"), "hello, compass")
      }

      func testPersonalizedGreetingUsesCoreLogic() throws {
        let request = GreetingRequest(name: "world", excited: true)
        XCTAssertEqual(try personalizedGreeting(request: request), "hello, world!")
      }

      func testBlankNameThrowsCoreError() {
        let request = GreetingRequest(name: "  ", excited: false)
        XCTAssertThrowsError(try personalizedGreeting(request: request)) { error in
          XCTAssertEqual(error as? GreetingError, .EmptyName)
        }
      }
    }
    """

  private static let macosInfoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleDisplayName</key>
        <string>GeneratedApp</string>
        <key>CFBundleExecutable</key>
        <string>GeneratedApp</string>
        <key>CFBundleIdentifier</key>
        <string>com.compass.generated.GeneratedApp</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>GeneratedApp</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleShortVersionString</key>
        <string>0.1.0</string>
        <key>CFBundleVersion</key>
        <string>1</string>
        <key>LSMinimumSystemVersion</key>
        <string>14.0</string>
        <key>NSPrincipalClass</key>
        <string>NSApplication</string>
    </dict>
    </plist>
    """

  private static let swiftFormatConfig = """
    {
      "indentation": { "spaces": 2 },
      "lineLength": 100,
      "version": 1
    }
    """

  private static let generateBindingsScript = #"""
    #!/usr/bin/env bash
    # Regenerates the UniFFI Swift bindings and C header for apps/macos.
    set -euo pipefail

    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    cd "$ROOT"

    if [[ ! -f crates/ffi/Cargo.toml ]]; then
      echo "generate-bindings requires crates/ffi (UniFFI)." >&2
      exit 1
    fi

    cargo build -p app-ffi --release

    LIB_DIR="$ROOT/target/release"
    DYLIB="$LIB_DIR/libapp_ffi.dylib"
    STATIC="$LIB_DIR/libapp_ffi.a"
    if [[ ! -f "$DYLIB" || ! -f "$STATIC" ]]; then
      echo "missing app-ffi artifacts in $LIB_DIR (need cdylib + staticlib)" >&2
      exit 1
    fi

    STAGING="$(mktemp -d)"
    trap 'rm -rf "$STAGING"' EXIT

    cargo run -q -p app-ffi --bin uniffi-bindgen -- generate \
      --library "$DYLIB" \
      --language swift \
      --out-dir "$STAGING"

    if [[ ! -f "$STAGING/app_ffi.swift" || ! -f "$STAGING/app_ffiFFI.h" ]]; then
      echo "UniFFI did not emit the expected Swift bindings" >&2
      ls -la "$STAGING" >&2 || true
      exit 1
    fi

    mkdir -p "$ROOT/apps/macos/Sources/AppFFI" "$ROOT/apps/macos/Sources/app_ffiFFI/include"
    cp "$STAGING/app_ffi.swift" "$ROOT/apps/macos/Sources/AppFFI/app_ffi.swift"
    cp "$STAGING/app_ffiFFI.h" "$ROOT/apps/macos/Sources/app_ffiFFI/include/app_ffiFFI.h"

    echo "bindings regenerated"
    """#

  private static let bundleMacOSScript = #"""
    #!/usr/bin/env bash
    # Builds an ad-hoc signed GeneratedApp.app under apps/macos/dist/.
    set -euo pipefail

    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    cd "$ROOT"

    bash "$ROOT/scripts/generate-bindings.sh"

    cd "$ROOT/apps/macos"
    swift build -c release

    APP="$ROOT/apps/macos/dist/GeneratedApp.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$ROOT/apps/macos/Info.plist" "$APP/Contents/Info.plist"
    cp "$ROOT/apps/macos/.build/release/GeneratedApp" "$APP/Contents/MacOS/GeneratedApp"

    if command -v codesign >/dev/null 2>&1; then
      codesign --force --sign - "$APP"
    fi

    echo "bundled $APP"
    """#

  private static let macosAXSmokeSwift = #"""
    import AppKit
    import ApplicationServices
    import Foundation

    /// One-shot Accessibility smoke for GeneratedApp. Finds the running app by
    /// bundle id, waits for SwiftUI accessibilityIdentifier values, and asserts
    /// the greeting copy matches crates/core via UniFFI.
    enum AXSmokeError: Error, CustomStringConvertible {
      case accessibilityTrusted
      case appNotFound(String)
      case elementMissing(String)
      case valueMismatch(id: String, expected: String, actual: String)

      var description: String {
        switch self {
        case .accessibilityTrusted:
          return "AXIsProcessTrusted() is false; grant Accessibility to this helper in System Settings, or set COMPASS_MACOS_UI_SMOKE=0 to skip."
        case .appNotFound(let bundleID):
          return "No running app with bundle id \(bundleID)."
        case .elementMissing(let id):
          return "Accessibility element '\(id)' not found."
        case .valueMismatch(let id, let expected, let actual):
          return "Accessibility element '\(id)' expected \(expected.debugDescription), got \(actual.debugDescription)."
        }
      }
    }

    let bundleID = CommandLine.arguments.count > 1
      ? CommandLine.arguments[1]
      : "com.compass.generated.GeneratedApp"
    let expectedLabel = CommandLine.arguments.count > 2
      ? CommandLine.arguments[2]
      : "hello, world!"
    let expectedCaption = CommandLine.arguments.count > 3
      ? CommandLine.arguments[3]
      : "Core logic lives in crates/core; this shell is SwiftUI only."
    let timeoutSeconds = CommandLine.arguments.count > 4
      ? (Double(CommandLine.arguments[4]) ?? 30)
      : 30

    do {
      try run(
        bundleID: bundleID,
        expectedLabel: expectedLabel,
        expectedCaption: expectedCaption,
        timeoutSeconds: timeoutSeconds
      )
      fputs("macos-ax-smoke ok\n", stdout)
      exit(0)
    } catch {
      fputs("macos-ax-smoke failed: \(error)\n", stderr)
      exit(1)
    }

    func run(
      bundleID: String,
      expectedLabel: String,
      expectedCaption: String,
      timeoutSeconds: Double
    ) throws {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      if !AXIsProcessTrustedWithOptions(options) {
        throw AXSmokeError.accessibilityTrusted
      }

      let deadline = Date().addingTimeInterval(timeoutSeconds)
      var appElement: AXUIElement?
      while Date() < deadline {
        if let pid = pid(forBundleID: bundleID) {
          appElement = AXUIElementCreateApplication(pid)
          break
        }
        Thread.sleep(forTimeInterval: 0.25)
      }
      guard let app = appElement else {
        throw AXSmokeError.appNotFound(bundleID)
      }

      let label = try waitForValue(
        in: app,
        identifier: "greeting.label",
        deadline: deadline
      )
      let caption = try waitForValue(
        in: app,
        identifier: "greeting.caption",
        deadline: deadline
      )
      if label != expectedLabel {
        throw AXSmokeError.valueMismatch(
          id: "greeting.label", expected: expectedLabel, actual: label)
      }
      if caption != expectedCaption {
        throw AXSmokeError.valueMismatch(
          id: "greeting.caption", expected: expectedCaption, actual: caption)
      }
    }

    func pid(forBundleID bundleID: String) -> pid_t? {
      let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      return apps.first?.processIdentifier
    }

    func waitForValue(
      in root: AXUIElement,
      identifier: String,
      deadline: Date
    ) throws -> String {
      while Date() < deadline {
        if let value = findValue(in: root, identifier: identifier) {
          return value
        }
        Thread.sleep(forTimeInterval: 0.25)
      }
      throw AXSmokeError.elementMissing(identifier)
    }

    func findValue(in element: AXUIElement, identifier: String) -> String? {
      if let id = copyStringAttribute(element, kAXIdentifierAttribute as String),
        id == identifier
      {
        if let value = copyStringAttribute(element, kAXValueAttribute as String), !value.isEmpty {
          return value
        }
        if let title = copyStringAttribute(element, kAXTitleAttribute as String), !title.isEmpty {
          return title
        }
        if let desc = copyStringAttribute(element, kAXDescriptionAttribute as String), !desc.isEmpty
        {
          return desc
        }
      }

      var childrenRef: CFTypeRef?
      let status = AXUIElementCopyAttributeValue(
        element, kAXChildrenAttribute as CFString, &childrenRef)
      guard status == .success, let children = childrenRef as? [AXUIElement] else {
        return nil
      }
      for child in children {
        if let value = findValue(in: child, identifier: identifier) {
          return value
        }
      }
      return nil
    }

    func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
      var ref: CFTypeRef?
      let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
      guard status == .success else { return nil }
      if let string = ref as? String { return string }
      if let number = ref as? NSNumber { return number.stringValue }
      return nil
    }
    """#

  private static let macosUISmokeScript = #"""
    #!/usr/bin/env bash
    # Launch GeneratedApp in a GUI session, assert Accessibility identifiers,
    # and capture a screenshot for audit. Intended to run inside the Compass
    # macOS VM (or any headed Mac). Set COMPASS_MACOS_UI_SMOKE=0 to skip.
    set -euo pipefail

    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    cd "$ROOT"

    if [[ "${COMPASS_MACOS_UI_SMOKE:-1}" == "0" || "${COMPASS_MACOS_UI_SMOKE:-1}" == "false" ]]; then
      echo "COMPASS_MACOS_UI_SMOKE disabled; skipping UI smoke"
      exit 0
    fi

    BUNDLE_ID="com.compass.generated.GeneratedApp"
    APP="$ROOT/apps/macos/dist/GeneratedApp.app"
    SHOT="$ROOT/apps/macos/dist/ui-smoke.png"
    AX_SRC="$ROOT/scripts/macos-ax-smoke.swift"
    AX_BIN="$(mktemp -t macos-ax-smoke)"
    EXPECTED_LABEL="hello, world!"
    EXPECTED_CAPTION="Core logic lives in crates/core; this shell is SwiftUI only."

    cleanup() {
      /usr/bin/killall GeneratedApp 2>/dev/null || true
      rm -f "$AX_BIN"
    }
    trap cleanup EXIT

    bash "$ROOT/scripts/bundle-macos.sh"
    if [[ ! -d "$APP" ]]; then
      echo "bundled app missing at $APP" >&2
      exit 1
    fi

    console_owner="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || echo loginwindow)"
    if [[ "$console_owner" == "loginwindow" || "$console_owner" == "_unknown" || -z "$console_owner" ]]; then
      echo "No GUI session on /dev/console (owner=$console_owner). Repair auto-login and retry." >&2
      exit 1
    fi

    GUI_UID="$(/usr/bin/id -u "$console_owner" 2>/dev/null || true)"
    if [[ -z "${GUI_UID:-}" ]]; then
      echo "Could not resolve uid for console owner $console_owner" >&2
      exit 1
    fi

    /usr/bin/killall GeneratedApp 2>/dev/null || true
    rm -f "$SHOT"

    # Compile AX helper for the guest toolchain (no Xcode project required).
    /usr/bin/swiftc -O -framework ApplicationServices -framework AppKit \
      -o "$AX_BIN" "$AX_SRC"

    # Launch into the auto-logged-in Aqua session (LaunchDaemon bash is not enough).
    /bin/launchctl asuser "$GUI_UID" /usr/bin/open -n "$APP"

    # Wait until the process is visible, then AX-assert greeting copy.
    /bin/launchctl asuser "$GUI_UID" "$AX_BIN" \
      "$BUNDLE_ID" "$EXPECTED_LABEL" "$EXPECTED_CAPTION" 45

    # Capture product pixels from the GUI session.
    /bin/launchctl asuser "$GUI_UID" /usr/sbin/screencapture -x "$SHOT"
    if [[ ! -f "$SHOT" ]]; then
      echo "screencapture did not produce $SHOT" >&2
      exit 1
    fi

    echo "macos ui smoke ok ($SHOT)"
    """#

  private static let verifyMacOSScript = #"""
    #!/usr/bin/env bash
    # macOS product verify. Runs inside the embedded macOS VM: build/test,
    # then launch + Accessibility assert + screenshot of GeneratedApp.
    set -euo pipefail

    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    cd "$ROOT"

    if ! command -v swift >/dev/null 2>&1; then
      echo "macos product requires a Mac host/VM with the Swift toolchain (Xcode)." >&2
      exit 1
    fi

    if [[ ! -f crates/ffi/Cargo.toml ]]; then
      echo "macos verify requires crates/ffi (UniFFI)." >&2
      exit 1
    fi

    # Builds the Rust FFI crate (cdylib + staticlib) and regenerates bindings.
    bash "$ROOT/scripts/generate-bindings.sh"

    cd "$ROOT/apps/macos"
    swift build -c release
    # Compiles the generated UniFFI bindings and runs the FFI round-trip tests,
    # proving Swift output matches crates/core behavior.
    swift test

    if xcrun -f swift-format >/dev/null 2>&1; then
      xcrun swift-format lint --strict --recursive \
        --configuration "$ROOT/.swift-format" \
        Sources/GeneratedApp Tests
    elif command -v swift-format >/dev/null 2>&1; then
      swift-format lint --strict --recursive \
        --configuration "$ROOT/.swift-format" \
        Sources/GeneratedApp Tests
    else
      echo "swift-format not found; skipping Swift lint"
    fi

    # Product-runtime smoke: bundle, launch in GUI session, AX assert, screenshot.
    bash "$ROOT/scripts/macos-ui-smoke.sh"

    echo "macos verify ok"
    """#
}
