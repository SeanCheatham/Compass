import Foundation

/// Root + `crates/core` scaffold templates.
public enum RustScaffoldCoreTemplates {
  public static func gitignore(hasMacOS: Bool) -> String {
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

  public static func workspaceManifest(hasCLI: Bool, hasMacOS: Bool, hasServer: Bool = false)
    -> String
  {
    var members = ["\"crates/core\""]
    if hasCLI { members.append("\"crates/cli\"") }
    if hasServer { members.append("\"crates/server\"") }
    if hasMacOS {
      members.append("\"crates/ui\"")
      members.append("\"crates/ffi\"")
    }
    var dependencyLines = [
      "app-core = { path = \"crates/core\" }"
    ]
    if hasServer {
      dependencyLines.append("axum = \"0.8\"")
      dependencyLines.append("tokio = { version = \"1\", features = [\"macros\", \"rt-multi-thread\"] }")
      dependencyLines.append("tower = \"0.5\"")
      dependencyLines.append("http-body-util = \"0.1\"")
    }
    if hasMacOS {
      dependencyLines.append("app-ui = { path = \"crates/ui\" }")
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

  public static let rustToolchain = """
    [toolchain]
    channel = "stable"
    components = ["rustfmt", "clippy"]
    """

  public static func readme(
    projectName: String, hasCLI: Bool, hasMacOS: Bool, hasServer: Bool = false
  ) -> String {
    var layout: [String] = [
      "- `crates/core`: shared Rust domain logic (required)"
    ]
    if hasCLI {
      layout.append("- `crates/cli`: command-line product over `core`")
    }
    if hasServer {
      layout.append("- `crates/server`: HTTP server product (axum) over `core`")
    }
    if hasMacOS {
      layout.append("- `crates/ui`: ViewState / Action / simulation / guardrails (UI policy)")
      layout.append("- `crates/ffi`: UniFFI exports over `ui` (+ `core` as needed)")
      layout.append(
        "- `apps/macos`: thin SwiftUI binder (no domain or UI policy) over UniFFI")
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
    if hasServer {
      commands += """
        - Run server: `cargo run -p app-server`
        """
    }
    if hasMacOS {
      commands += """
        - Bindings (macOS): `bash scripts/generate-bindings.sh`
        - Verify (macOS adapter): `bash scripts/verify-macos.sh`
        - Headed fidelity (opt-in): `COMPASS_MACOS_UI_FIDELITY=1 bash scripts/verify-macos.sh`
        - Bundle (macOS): `bash scripts/bundle-macos.sh`
        """
    }
    let products = [
      hasCLI ? "cli" : nil,
      hasServer ? "server" : nil,
      hasMacOS ? "macos" : nil,
    ].compactMap { $0 }.joined(separator: "+")
    let adapters = [
      hasCLI ? "CLI" : nil,
      hasServer ? "server" : nil,
      hasMacOS ? "macOS" : nil,
    ].compactMap { $0 }.joined(separator: ", ")
    return """
      # \(projectName)

      A Compass-generated project with required Rust `crates/core` and products: \(products).

      Domain logic lives in `crates/core`. UI policy lives in `crates/ui`. \(adapters) are adapters.

      ## Current status

      - Scaffold greeting smoke path is wired through core\(hasCLI ? " / CLI" : "")\(hasServer ? " / server" : "")\(hasMacOS ? " / macOS" : "").
      - Replace the greeting with real product behavior in thin end-to-end slices.

      ## Layout

      \(layout.joined(separator: "\n"))

      ## Commands

      \(commands)
      """
  }

  public static let coreManifest = """
    [package]
    name = "app-core"
    edition.workspace = true
    license.workspace = true
    version.workspace = true
    """

  public static let coreLib = """
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

}
