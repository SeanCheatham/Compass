import Foundation

enum RustProjectScaffold {
  struct Options: Equatable, Sendable {
    var projectName: String

    init(projectName: String) {
      self.projectName = Self.displayName(projectName)
    }

    private static func displayName(_ raw: String) -> String {
      let cleaned =
        raw
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return cleaned.isEmpty ? "Compass Rust App" : String(cleaned.prefix(80))
    }
  }

  struct ScaffoldFile: Equatable, Sendable {
    var path: String
    var contents: String
  }

  static func files(options: Options) -> [ScaffoldFile] {
    let name = options.projectName
    return [
      ScaffoldFile(path: ".gitignore", contents: gitignore),
      ScaffoldFile(path: "Cargo.toml", contents: workspaceManifest),
      ScaffoldFile(path: "rust-toolchain.toml", contents: rustToolchain),
      ScaffoldFile(path: "README.md", contents: readme(projectName: name)),
      ScaffoldFile(path: "crates/app-core/Cargo.toml", contents: appCoreManifest),
      ScaffoldFile(path: "crates/app-core/src/lib.rs", contents: appCoreLib),
      ScaffoldFile(path: "crates/app-cli/Cargo.toml", contents: appCLIManifest),
      ScaffoldFile(path: "crates/app-cli/src/main.rs", contents: appCLIMain),
      ScaffoldFile(path: "crates/app-cli/tests/cli_smoke.rs", contents: appCLISmokeTest),
    ]
  }

  static func write(to url: URL, options: Options) throws {
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
    }
  }

  static func isGeneratedWorkspace(at url: URL) -> Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: url.appending(path: "Cargo.toml").path)
      && fm.fileExists(atPath: url.appending(path: "crates/app-core/Cargo.toml").path)
      && fm.fileExists(atPath: url.appending(path: "crates/app-cli/Cargo.toml").path)
  }

  private static let gitignore = """
    /target/
    .DS_Store
    *.log
    """

  private static let workspaceManifest = """
    [workspace]
    resolver = "2"
    members = [
      "crates/app-core",
      "crates/app-cli",
    ]

    [workspace.package]
    edition = "2021"
    license = "MIT"
    version = "0.1.0"

    [workspace.dependencies]
    app-core = { path = "crates/app-core" }
    """

  private static let rustToolchain = """
    [toolchain]
    channel = "stable"
    components = ["rustfmt", "clippy"]
    """

  private static func readme(projectName: String) -> String {
    """
    # \(projectName)

    A Compass-generated Rust Cargo workspace (backend/CLI only).

    ## Layout

    - `crates/app-core`: shared library and domain logic
    - `crates/app-cli`: command-line entry point

    ## Commands

    - Format: `cargo fmt --all --check`
    - Lint: `cargo clippy --workspace --all-targets --all-features -- -D warnings`
    - Test: `cargo test --workspace`
    - Coverage: `cargo llvm-cov --workspace --summary-only`
    - Verify: `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace`
    - Run CLI: `cargo run -p app-cli -- status`
    """
  }

  private static let appCoreManifest = """
    [package]
    name = "app-core"
    edition.workspace = true
    license.workspace = true
    version.workspace = true
    """

  private static let appCoreLib = """
    /// Minimal greeting used by the scaffold CLI smoke path.
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

  private static let appCLIManifest = """
    [package]
    name = "app-cli"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [dependencies]
    app-core.workspace = true
    """

  private static let appCLIMain = """
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

  private static let appCLISmokeTest = """
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
}
