import Foundation

/// Identifiers for toolchains available in the Compass Shared VM guest.
public enum SharedVMToolchainID: String, CaseIterable, Sendable, Equatable {
  case commandLineTools = "command_line_tools"
  case homebrew
  case ripgrep
  case rust
  case cargoLlvmCov = "cargo_llvm_cov"
  case cargoMutants = "cargo_mutants"
  case node
}

/// Guest paths and LaunchDaemon labels derived from a toolchain id.
enum SharedVMToolchainPaths {
  static let brewInstallPath = "/opt/homebrew/bin/brew"
  static let ripgrepInstallPath = "/usr/local/bin/rg"
  static let brewRipgrepPath = "/opt/homebrew/bin/rg"

  static func scriptGuestPath(id: String) -> String {
    "/usr/local/libexec/compass-install-\(id).sh"
  }

  static func logGuestPath(id: String) -> String {
    "/var/log/compass-toolchain-\(id).log"
  }

  static func doneSentinelGuestPath(id: String) -> String {
    "/var/log/compass-toolchain-\(id).done"
  }

  static func installLaunchDaemonLabel(id: String) -> String {
    "com.seancheatham.Compass.toolchain-\(id)"
  }

  static func installLaunchDaemonPlistGuestPath(id: String) -> String {
    "/Library/LaunchDaemons/com.seancheatham.Compass.toolchain-\(id).plist"
  }

  static func logTag(id: String) -> String {
    "[compass-toolchain-\(id)]"
  }
}

/// One entry in the Shared VM toolchain catalog.
public struct SharedVMToolchainDefinition: Sendable, Equatable {
  public let id: SharedVMToolchainID
  public let displayName: String
  public let description: String
  public let defaultProvisioned: Bool
  /// Dependency ids that must be present before this toolchain installs.
  public let dependencies: [SharedVMToolchainID]
  public let probeCommand: String
  public let installTimeout: TimeInterval
  /// When false, `install_toolchain` rejects the id (e.g. CLT uses
  /// `SharedCompassVMDevToolsProvisioner` instead of the generic path).
  public let installableViaGenericProvisioner: Bool

  var stringID: String { id.rawValue }

  func logTag() -> String { SharedVMToolchainPaths.logTag(id: stringID) }

  public func renderInstallScript() -> String {
    switch id {
    case .commandLineTools:
      fatalError("command_line_tools is installed by SharedCompassVMDevToolsProvisioner")
    case .homebrew:
      return Self.renderHomebrewInstallScript()
    case .ripgrep:
      return Self.renderRipgrepInstallScript()
    case .rust:
      return Self.renderRustInstallScript()
    case .cargoLlvmCov:
      return Self.renderCargoComponentInstallScript(
        id: SharedVMToolchainID.cargoLlvmCov.rawValue,
        crate: "cargo-llvm-cov",
        verificationCommand: "/usr/local/bin/cargo llvm-cov --version"
      )
    case .cargoMutants:
      return Self.renderCargoComponentInstallScript(
        id: SharedVMToolchainID.cargoMutants.rawValue,
        crate: "cargo-mutants",
        verificationCommand: "/usr/local/bin/cargo mutants --version"
      )
    case .node:
      return Self.renderNodeInstallScript()
    }
  }

  func finaliseVerificationCommand() -> String {
    switch id {
    case .commandLineTools:
      return "xcode-select -p >/dev/null 2>&1"
    case .homebrew:
      return
        "test -x \(SharedVMToolchainPaths.brewInstallPath) && \(SharedVMToolchainPaths.brewInstallPath) --version >/dev/null 2>&1"
    case .ripgrep:
      return """
        test -x \(SharedVMToolchainPaths.ripgrepInstallPath)
        \(SharedVMToolchainPaths.ripgrepInstallPath) --version >/dev/null 2>&1
        """
    case .rust:
      return """
        \(Self.rustVerificationCommand) >/dev/null 2>&1
        """
    case .cargoLlvmCov:
      return "/usr/local/bin/cargo llvm-cov --version >/dev/null 2>&1"
    case .cargoMutants:
      return "/usr/local/bin/cargo mutants --version >/dev/null 2>&1"
    case .node:
      return """
        \(Self.nodeVerificationCommand) >/dev/null 2>&1
        """
    }
  }

  /// PATH-independent check that the rustup toolchain is usable. The
  /// guest agent runs bash non-interactively, so rustup's proxies are
  /// symlinked into /usr/local/bin at install time.
  public static let rustVerificationCommand =    "test -x /usr/local/bin/cargo && /usr/local/bin/cargo --version && /usr/local/bin/rustc --version && /usr/local/bin/rustfmt --version && /usr/local/bin/cargo-clippy --version"

  static let rustProbeCommand = """
    test -x /usr/local/bin/cargo && test -x /usr/local/bin/rustc && echo PRESENT || echo MISSING
    """

  /// Login-shell check that the generated TypeScript toolchain is on PATH.
  static let nodeVerificationCommand =
    "command -v node && command -v npm && command -v npx && command -v corepack && command -v pnpm && command -v tsc && node --version && pnpm --version && tsc --version"

  static let nodeProbeCommand = """
    command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v npx >/dev/null 2>&1 && command -v corepack >/dev/null 2>&1 && command -v pnpm >/dev/null 2>&1 && command -v tsc >/dev/null 2>&1 && echo PRESENT || echo MISSING
    """

  func parseProgressFraction(fromLogTail tail: String) -> Double {
    let lower = tail.lowercased()
    let tag = logTag().lowercased()
    if lower.contains("exit=0") { return 1.0 }
    if lower.contains("\(tag) installed") || lower.contains("\(tag) already installed") {
      return 0.9
    }
    if lower.contains("install") || lower.contains("bootstrapping") {
      return 0.5
    }
    if lower.contains("\(tag) starting") { return 0.1 }
    return 0.2
  }

  // MARK: - Install script renderers

  private static func renderScriptShell(
    id: String,
    body: String
  ) -> String {
    let logPath = SharedVMToolchainPaths.logGuestPath(id: id)
    let donePath = SharedVMToolchainPaths.doneSentinelGuestPath(id: id)
    let tag = SharedVMToolchainPaths.logTag(id: id)
    return """
      #!/bin/bash
      # Compass toolchain installer: \(id)
      set -euo pipefail
      umask 022

      LOG_PATH="\(logPath)"
      DONE_PATH="\(donePath)"
      TAG="\(tag)"

      fail() {
        local code="$1"
        shift
        echo "$TAG ERROR: $*"
        echo "exit=$code" > "$DONE_PATH"
        exit "$code"
      }

      exec > "$LOG_PATH" 2>&1
      echo "$TAG $(date -u '+%Y-%m-%dT%H:%M:%SZ') starting"

      \(body)

      echo "exit=0" > "$DONE_PATH"
      exit 0
      """
  }

  private static func renderHomebrewInstallScript() -> String {
    let id = SharedVMToolchainID.homebrew.rawValue
    let brewBin = SharedVMToolchainPaths.brewInstallPath
    let guestUser = SharedCompassVMBundle.State.defaultGuestUserName
    return renderScriptShell(
      id: id,
      body: """
        BREW_BIN="\(brewBin)"
        GUEST_USER="\(guestUser)"
        if [ -x "$BREW_BIN" ]; then
          echo "\(SharedVMToolchainPaths.logTag(id: id)) already installed"
        else
          echo "\(SharedVMToolchainPaths.logTag(id: id)) bootstrapping Homebrew as $GUEST_USER"
          su - "$GUEST_USER" -c 'NONINTERACTIVE=1 CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \\
            || fail 2 "Homebrew bootstrap failed"
          [ -x "$BREW_BIN" ] || fail 3 "Homebrew missing at $BREW_BIN after bootstrap"
          echo "\(SharedVMToolchainPaths.logTag(id: id)) installed $BREW_BIN"
        fi
        """)
  }

  private static func renderRipgrepInstallScript() -> String {
    let id = SharedVMToolchainID.ripgrep.rawValue
    let rgBin = SharedVMToolchainPaths.ripgrepInstallPath
    let brewRg = SharedVMToolchainPaths.brewRipgrepPath
    let brewBin = SharedVMToolchainPaths.brewInstallPath
    let guestUser = SharedCompassVMBundle.State.defaultGuestUserName
    return renderScriptShell(
      id: id,
      body: """
        RG_BIN="\(rgBin)"
        BREW_RG="\(brewRg)"
        BREW_BIN="\(brewBin)"
        GUEST_USER="\(guestUser)"
        if [ -x "$RG_BIN" ]; then
          echo "\(SharedVMToolchainPaths.logTag(id: id)) already installed"
        else
          [ -x "$BREW_BIN" ] || fail 2 "Homebrew missing — install the homebrew toolchain first"
          echo "\(SharedVMToolchainPaths.logTag(id: id)) brew install ripgrep"
          su - "$GUEST_USER" -c "'$BREW_BIN' install ripgrep" \\
            || fail 3 "brew install ripgrep failed"
          [ -x "$BREW_RG" ] || fail 4 "ripgrep missing at $BREW_RG after brew install"
          install -d -o root -g wheel -m 0755 "$(dirname "$RG_BIN")"
          ln -sf "$BREW_RG" "$RG_BIN"
          [ -x "$RG_BIN" ] || fail 5 "ripgrep symlink verification failed at $RG_BIN"
          echo "\(SharedVMToolchainPaths.logTag(id: id)) installed $RG_BIN"
        fi
        """)
  }

  private static func renderRustInstallScript() -> String {
    let id = SharedVMToolchainID.rust.rawValue
    let guestUser = SharedCompassVMBundle.State.defaultGuestUserName
    return renderScriptShell(
      id: id,
      body: """
        GUEST_USER="\(guestUser)"
        GUEST_HOME="$(eval echo ~"$GUEST_USER")"
        # Verification must run as the guest user: rustup's proxies resolve
        # the toolchain from the invoking user's home, so a root-run probe
        # (this script runs as root) would fail against /var/root/.rustup
        # even when the guest user's toolchain is healthy.
        if su - "$GUEST_USER" -c '\(rustVerificationCommand)' >/dev/null 2>&1; then
          echo "\(SharedVMToolchainPaths.logTag(id: id)) already installed"
        else
          if [ ! -x "$GUEST_HOME/.cargo/bin/rustup" ]; then
            echo "\(SharedVMToolchainPaths.logTag(id: id)) installing rustup stable toolchain"
            su - "$GUEST_USER" -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default --component rustfmt --component clippy' \\
              || fail 2 "rustup install failed"
          else
            echo "\(SharedVMToolchainPaths.logTag(id: id)) rustup present, ensuring components"
            su - "$GUEST_USER" -c '"$HOME/.cargo/bin/rustup" component add rustfmt clippy' \\
              || fail 3 "rustup component add failed"
          fi
          # The guest agent's bash is non-interactive and never sources
          # the login profile, so expose the rustup proxies on the
          # default PATH via /usr/local/bin.
          install -d -o root -g wheel -m 0755 /usr/local/bin
          for tool in cargo rustc rustfmt cargo-clippy clippy-driver rustup; do
            if [ -x "$GUEST_HOME/.cargo/bin/$tool" ]; then
              ln -sf "$GUEST_HOME/.cargo/bin/$tool" "/usr/local/bin/$tool"
            fi
          done
          su - "$GUEST_USER" -c '\(rustVerificationCommand)' >/dev/null 2>&1 \\
            || fail 4 "rust toolchain verification failed"
          echo "\(SharedVMToolchainPaths.logTag(id: id)) installed rustup stable toolchain"
        fi
        """)
  }

  private static func renderCargoComponentInstallScript(
    id: String,
    crate: String,
    verificationCommand: String
  ) -> String {
    let guestUser = SharedCompassVMBundle.State.defaultGuestUserName
    return renderScriptShell(
      id: id,
      body: """
        GUEST_USER="\(guestUser)"
        if su - "$GUEST_USER" -c '\(verificationCommand)' >/dev/null 2>&1; then
          echo "\(SharedVMToolchainPaths.logTag(id: id)) already installed"
        else
          su - "$GUEST_USER" -c '\(rustVerificationCommand)' >/dev/null 2>&1 \\
            || fail 2 "Rust toolchain missing — install the rust toolchain first"
          echo "\(SharedVMToolchainPaths.logTag(id: id)) cargo install \(crate) --locked"
          su - "$GUEST_USER" -c '/usr/local/bin/cargo install \(crate) --locked' \\
            || fail 3 "cargo install \(crate) failed"
          su - "$GUEST_USER" -c '\(verificationCommand)' >/dev/null 2>&1 \\
            || fail 4 "\(crate) verification failed"
          echo "\(SharedVMToolchainPaths.logTag(id: id)) installed \(crate)"
        fi
        """)
  }

  private static func renderNodeInstallScript() -> String {
    let id = SharedVMToolchainID.node.rawValue
    let brewBin = SharedVMToolchainPaths.brewInstallPath
    let guestUser = SharedCompassVMBundle.State.defaultGuestUserName
    return renderScriptShell(
      id: id,
      body: """
        BREW_BIN="\(brewBin)"
        GUEST_USER="\(guestUser)"
        if su - "$GUEST_USER" -c '\(nodeVerificationCommand)' >/dev/null 2>&1; then
          echo "\(SharedVMToolchainPaths.logTag(id: id)) already installed"
        else
          [ -x "$BREW_BIN" ] || fail 2 "Homebrew missing — install the homebrew toolchain first"
          if ! su - "$GUEST_USER" -c 'command -v node' >/dev/null 2>&1; then
            echo "\(SharedVMToolchainPaths.logTag(id: id)) brew install node"
            su - "$GUEST_USER" -c "'$BREW_BIN' install node" \\
              || fail 3 "brew install node failed"
          fi
          su - "$GUEST_USER" -c 'command -v node && command -v npm && command -v npx && command -v corepack && node --version && npm --version' \\
            || fail 4 "node/npm/npx verification failed"
          su - "$GUEST_USER" -c 'corepack enable && corepack prepare pnpm@9.15.4 --activate' \\
            || fail 5 "corepack pnpm activation failed"
          if ! su - "$GUEST_USER" -c 'command -v tsc' >/dev/null 2>&1; then
            echo "\(SharedVMToolchainPaths.logTag(id: id)) npm install -g typescript"
            su - "$GUEST_USER" -c 'npm install -g typescript' \\
              || fail 6 "npm install -g typescript failed"
          fi
          su - "$GUEST_USER" -c '\(nodeVerificationCommand)' \\
            || fail 7 "node/pnpm/typescript verification failed"
          echo "\(SharedVMToolchainPaths.logTag(id: id)) installed node, npm, corepack, pnpm, and typescript"
        fi
        """)
  }

}

/// Static registry of Shared VM toolchains.
public enum SharedVMToolchainCatalog {
  public static let all: [SharedVMToolchainDefinition] = [
    SharedVMToolchainDefinition(
      id: .commandLineTools,
      displayName: "Xcode Command Line Tools",
      description:
        "clang, git, make, Swift, and the macOS SDK. Required for baseline guest development tooling.",
      defaultProvisioned: true,
      dependencies: [],
      probeCommand: "xcode-select -p >/dev/null 2>&1 && echo PRESENT || echo MISSING",
      installTimeout: 60 * 60,
      installableViaGenericProvisioner: false
    ),
    SharedVMToolchainDefinition(
      id: .homebrew,
      displayName: "Homebrew",
      description: "Package manager used to install optional language toolchains in the guest.",
      defaultProvisioned: true,
      dependencies: [],
      probeCommand:
        "[ -x \(SharedVMToolchainPaths.brewInstallPath) ] && echo PRESENT || echo MISSING",
      installTimeout: 30 * 60,
      installableViaGenericProvisioner: true
    ),
    SharedVMToolchainDefinition(
      id: .ripgrep,
      displayName: "ripgrep",
      description: "Fast code search (`rg`) used by Compass agent grep tooling.",
      defaultProvisioned: true,
      dependencies: [.homebrew],
      probeCommand:
        "[ -x \(SharedVMToolchainPaths.ripgrepInstallPath) ] && echo PRESENT || echo MISSING",
      installTimeout: 15 * 60,
      installableViaGenericProvisioner: true
    ),
    SharedVMToolchainDefinition(
      id: .rust,
      displayName: "Rust (rustup stable)",
      description:
        "rustup-managed stable Rust (cargo, rustc, rustfmt, clippy) for building generated Rust workspaces in the guest.",
      defaultProvisioned: true,
      dependencies: [],
      probeCommand: SharedVMToolchainDefinition.rustProbeCommand,
      installTimeout: 30 * 60,
      installableViaGenericProvisioner: true
    ),
    SharedVMToolchainDefinition(
      id: .cargoLlvmCov,
      displayName: "cargo-llvm-cov",
      description: "Coverage collector used by the generated-project quality gates.",
      defaultProvisioned: true,
      dependencies: [.rust],
      probeCommand:
        "/usr/local/bin/cargo llvm-cov --version >/dev/null 2>&1 && echo PRESENT || echo MISSING",
      installTimeout: 60 * 60,
      installableViaGenericProvisioner: true
    ),
    SharedVMToolchainDefinition(
      id: .cargoMutants,
      displayName: "cargo-mutants",
      description: "Mutation testing used by the generated-project quality gates.",
      defaultProvisioned: true,
      dependencies: [.rust],
      probeCommand:
        "/usr/local/bin/cargo mutants --version >/dev/null 2>&1 && echo PRESENT || echo MISSING",
      installTimeout: 60 * 60,
      installableViaGenericProvisioner: true
    ),
    SharedVMToolchainDefinition(
      id: .node,
      displayName: "Node.js + pnpm (TypeScript)",
      description:
        "Optional Node.js toolchain with npm, Corepack/pnpm, and global TypeScript (`tsc`).",
      defaultProvisioned: false,
      dependencies: [.homebrew],
      probeCommand: SharedVMToolchainDefinition.nodeProbeCommand,
      installTimeout: 15 * 60,
      installableViaGenericProvisioner: true
    ),
  ]

  public static let defaultProvisionedIDs: [String] = all.filter(\.defaultProvisioned).map(\.stringID)

  public static func definition(for id: SharedVMToolchainID) -> SharedVMToolchainDefinition {
    guard let entry = all.first(where: { $0.id == id }) else {
      fatalError("Unknown toolchain id: \(id)")
    }
    return entry
  }

  static func definition(forStringID id: String) -> SharedVMToolchainDefinition? {
    all.first { $0.stringID == id }
  }

  /// Validates unique ids and acyclic dependencies. Traps on programmer error.
  static func validateCatalog() {
    let ids = Set(all.map(\.stringID))
    precondition(ids.count == all.count, "Duplicate toolchain ids in catalog")
    for entry in all {
      for dep in entry.dependencies {
        precondition(ids.contains(dep.rawValue), "Unknown dependency \(dep) for \(entry.id)")
        precondition(dep != entry.id, "Toolchain \(entry.id) depends on itself")
      }
    }
  }
}

private let _sharedVMToolchainCatalogValidated: Void = {
  SharedVMToolchainCatalog.validateCatalog()
}()
