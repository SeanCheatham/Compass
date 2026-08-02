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
        ScaffoldFile(path: "crates/ffi/Cargo.toml", contents: ffiManifest),
        ScaffoldFile(path: "crates/ffi/src/lib.rs", contents: ffiLib),
        ScaffoldFile(path: "crates/ffi/src/bin/uniffi-bindgen.rs", contents: ffiBindgenMain),
        ScaffoldFile(path: "apps/macos/Package.swift", contents: macosPackageSwift),
        ScaffoldFile(
          path: "apps/macos/Sources/GeneratedApp/GeneratedApp.swift",
          contents: macosAppSwift(projectName: name)
        ),
        ScaffoldFile(
          path: "apps/macos/Sources/GeneratedApp/GreetingBridge.swift",
          contents: macosGreetingBridge
        ),
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
      try file.contents.write(to: destination, atomically: true, encoding: .utf8)
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
        /apps/macos/Generated/
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
      layout.append("- `apps/macos`: thin SwiftUI shell (no domain logic)")
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
        - Verify (macOS, host/VM): `bash scripts/verify-macos.sh`
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

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn greeting_includes_name() {
            assert_eq!(greeting("compass"), "hello, compass");
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

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn greeting_matches_core() {
            assert_eq!(greeting("compass".into()), "hello, compass");
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
            .executableTarget(
                name: "GeneratedApp",
                path: "Sources/GeneratedApp"
            )
        ]
    )
    """

  private static func macosAppSwift(projectName: String) -> String {
    """
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
        private let message = GreetingBridge.greeting(name: "world")

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

  /// Smoke façade kept behaviorally identical to `app_core::greeting`.
  /// `scripts/verify-macos.sh` also regenerates UniFFI Swift under `apps/macos/Generated`.
  private static let macosGreetingBridge = #"""
    import Foundation

    enum GreetingBridge {
        static func greeting(name: String) -> String {
            "hello, \(name)"
        }
    }
    """#

  private static let verifyMacOSScript = #"""
    #!/usr/bin/env bash
    # Temporary host-side macOS verify. Swap this runner for a macOS VM later.
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

    cargo build -p app-ffi --release

    LIB_DIR="$ROOT/target/release"
    DYLIB="$LIB_DIR/libapp_ffi.dylib"
    if [[ ! -f "$DYLIB" ]]; then
      echo "missing UniFFI dylib at $DYLIB" >&2
      exit 1
    fi

    GEN="$ROOT/apps/macos/Generated"
    rm -rf "$GEN"
    mkdir -p "$GEN"
    cargo run -q -p app-ffi --bin uniffi-bindgen -- generate \
      --library "$DYLIB" \
      --language swift \
      --out-dir "$GEN"

    if [[ ! -f "$GEN/app_ffi.swift" ]]; then
      echo "UniFFI did not emit apps/macos/Generated/app_ffi.swift" >&2
      ls -la "$GEN" >&2 || true
      exit 1
    fi

    cd "$ROOT/apps/macos"
    swift build -c release

    echo "macos verify ok"
    """#
}
