import Foundation

/// macOS product scaffold templates (`crates/ui`, `crates/ffi`, `apps/macos`, scripts).
public enum RustScaffoldMacOSTemplates {
  public static let uiManifest = """
    [package]
    name = "app-ui"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [dependencies]
    app-core.workspace = true
    """

  public static let uiLib = #"""
    //! UI state, semantics, simulation, and guardrails.
    //!
    //! Domain rules stay in `app-core`. Platform shells bind `ViewState` only.

    use app_core::{greeting, personalized_greeting, GreetingRequest};

    /// Schema version for serialized / UniFFI view state.
    pub const SCHEMA_VERSION: u32 = 1;

    /// Stable caption for the greeting screen binder.
    pub const GREETING_CAPTION: &str = "UI policy lives in crates/ui; this shell is SwiftUI only.";

    /// Serializable presentation state for the greeting screen.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct ViewState {
        pub schema_version: u32,
        pub label: String,
        pub caption: String,
    }

    /// Closed vocabulary of user intents.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub enum Action {
        /// Rebuild greeting copy from domain defaults.
        Refresh,
    }

    /// I/O requests produced by `update`. Greeting update is pure.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub enum Effect {}

    /// Accessibility-inspired role for semantic nodes.
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum SemanticRole {
        Container,
        Text,
        Button,
    }

    /// Compass semantic tree node (ids are the binder / AX / sim contract).
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct SemanticNode {
        pub id: String,
        pub role: SemanticRole,
        pub value: String,
        pub actions: Vec<String>,
        pub children: Vec<SemanticNode>,
    }

    /// Build the initial greeting screen from `app-core`.
    pub fn initial_state() -> ViewState {
        let label = personalized_greeting(&GreetingRequest {
            name: "world".into(),
            excited: true,
        })
        .unwrap_or_else(|_| greeting("world"));
        ViewState {
            schema_version: SCHEMA_VERSION,
            label,
            caption: GREETING_CAPTION.to_string(),
        }
    }

    /// Pure UI update. Effects are reserved for future I/O.
    pub fn update(_state: ViewState, action: Action) -> (ViewState, Vec<Effect>) {
        match action {
            Action::Refresh => (initial_state(), Vec::new()),
        }
    }

    /// Derive the semantic tree from view state.
    pub fn semantic_tree(state: &ViewState) -> SemanticNode {
        SemanticNode {
            id: "root".into(),
            role: SemanticRole::Container,
            value: String::new(),
            actions: Vec::new(),
            children: vec![
                SemanticNode {
                    id: "greeting.label".into(),
                    role: SemanticRole::Text,
                    value: state.label.clone(),
                    actions: Vec::new(),
                    children: Vec::new(),
                },
                SemanticNode {
                    id: "greeting.caption".into(),
                    role: SemanticRole::Text,
                    value: state.caption.clone(),
                    actions: Vec::new(),
                    children: Vec::new(),
                },
            ],
        }
    }

    /// Find a node's value by stable id (depth-first).
    pub fn find_semantic_value<'a>(root: &'a SemanticNode, id: &str) -> Option<&'a str> {
        if root.id == id {
            return Some(root.value.as_str());
        }
        for child in &root.children {
            if let Some(value) = find_semantic_value(child, id) {
                return Some(value);
            }
        }
        None
    }

    /// One step in a simulation trace.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct TraceStep {
        pub action: Option<Action>,
        pub state: ViewState,
        pub semantic: SemanticNode,
    }

    /// Headless UI simulator: apply actions, record traces, query semantics.
    #[derive(Debug, Clone)]
    pub struct Simulator {
        pub state: ViewState,
        pub trace: Vec<TraceStep>,
    }

    impl Simulator {
        pub fn new(state: ViewState) -> Self {
            let semantic = semantic_tree(&state);
            let trace = vec![TraceStep {
                action: None,
                state: state.clone(),
                semantic,
            }];
            Self { state, trace }
        }

        pub fn apply(&mut self, action: Action) {
            let (next, _effects) = update(self.state.clone(), action.clone());
            self.state = next;
            let semantic = semantic_tree(&self.state);
            self.trace.push(TraceStep {
                action: Some(action),
                state: self.state.clone(),
                semantic,
            });
        }

        pub fn value(&self, id: &str) -> Option<&str> {
            find_semantic_value(&self.trace.last()?.semantic, id)
        }
    }

    /// Deterministic UI guardrail failures.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub enum GuardrailViolation {
        MissingRequiredId(String),
        EmptyId,
        EmptyTextValue(String),
    }

    impl std::fmt::Display for GuardrailViolation {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                Self::MissingRequiredId(id) => write!(f, "missing required semantic id `{id}`"),
                Self::EmptyId => write!(f, "semantic node has an empty id"),
                Self::EmptyTextValue(id) => write!(f, "text node `{id}` has an empty value"),
            }
        }
    }

    /// Required ids for the greeting screen.
    pub const REQUIRED_GREETING_IDS: &[&str] = &["greeting.label", "greeting.caption"];

    /// Check structural guardrails on a semantic tree.
    pub fn check_guardrails(root: &SemanticNode) -> Result<(), Vec<GuardrailViolation>> {
        let mut violations = Vec::new();
        walk_guardrails(root, &mut violations);
        for id in REQUIRED_GREETING_IDS {
            if find_semantic_value(root, id).is_none() {
                violations.push(GuardrailViolation::MissingRequiredId((*id).to_string()));
            }
        }
        if violations.is_empty() {
            Ok(())
        } else {
            Err(violations)
        }
    }

    fn walk_guardrails(node: &SemanticNode, violations: &mut Vec<GuardrailViolation>) {
        if node.id.trim().is_empty() {
            violations.push(GuardrailViolation::EmptyId);
        }
        if node.role == SemanticRole::Text && node.value.trim().is_empty() {
            violations.push(GuardrailViolation::EmptyTextValue(node.id.clone()));
        }
        for child in &node.children {
            walk_guardrails(child, violations);
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn initial_greeting_matches_core() {
            let state = initial_state();
            assert_eq!(state.schema_version, SCHEMA_VERSION);
            assert_eq!(state.label, "hello, world!");
            assert_eq!(state.caption, GREETING_CAPTION);
        }

        #[test]
        fn simulation_refresh_preserves_greeting_ids() {
            let mut sim = Simulator::new(initial_state());
            assert_eq!(sim.value("greeting.label"), Some("hello, world!"));
            assert_eq!(sim.value("greeting.caption"), Some(GREETING_CAPTION));
            sim.apply(Action::Refresh);
            assert_eq!(sim.value("greeting.label"), Some("hello, world!"));
            check_guardrails(&semantic_tree(&sim.state)).expect("guardrails");
        }

        #[test]
        fn guardrails_reject_missing_label() {
            let mut root = semantic_tree(&initial_state());
            root.children.retain(|child| child.id != "greeting.label");
            let err = check_guardrails(&root).expect_err("expected missing id");
            assert!(err.iter().any(|v| matches!(
                v,
                GuardrailViolation::MissingRequiredId(id) if id == "greeting.label"
            )));
        }
    }
    """#

  public static let ffiManifest = """
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
    app-ui.workspace = true
    uniffi = { workspace = true }

    [[bin]]
    name = "uniffi-bindgen"
    path = "src/bin/uniffi-bindgen.rs"
    """

  public static let ffiLib = """
    uniffi::setup_scaffolding!();

    /// Flat UniFFI snapshot of `app_ui::ViewState` for SwiftUI binders.
    #[derive(uniffi::Record)]
    pub struct UiSnapshot {
        pub schema_version: u32,
        pub label: String,
        pub caption: String,
    }

    impl From<app_ui::ViewState> for UiSnapshot {
        fn from(state: app_ui::ViewState) -> Self {
            Self {
                schema_version: state.schema_version,
                label: state.label,
                caption: state.caption,
            }
        }
    }

    /// Initial UI snapshot for the macOS / future iOS binder.
    #[uniffi::export]
    pub fn ui_initial_snapshot() -> UiSnapshot {
        app_ui::initial_state().into()
    }

    /// Dispatch `Refresh` and return the next snapshot.
    #[uniffi::export]
    pub fn ui_dispatch_refresh() -> UiSnapshot {
        let (next, _) = app_ui::update(app_ui::initial_state(), app_ui::Action::Refresh);
        next.into()
    }

    /// UniFFI export mirroring `app_core::greeting` for adapter smoke tests.
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
        fn ui_snapshot_matches_ui_crate() {
            let snap = ui_initial_snapshot();
            assert_eq!(snap.label, "hello, world!");
            assert!(snap.caption.contains("crates/ui"));
        }

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

  public static let ffiBindgenMain = """
    fn main() {
        uniffi::uniffi_bindgen_main()
    }
    """

  public static func macosPackageSwift(naming: RustProjectScaffold.MacOSNaming) -> String {
    """
    // swift-tools-version: 5.9
    import PackageDescription

    // Absolute path via Context.packageDirectory so SPM resolves the UniFFI
    // staticlib regardless of the caller's cwd. Bindings scripts build release.
    let ffiStaticLib =
      "\\(Context.packageDirectory)/../../target/release/libapp_ffi.a"

    let package = Package(
        name: "\(naming.moduleName)",
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
                    .unsafeFlags([ffiStaticLib])
                ]
            ),
            .executableTarget(
                name: "\(naming.moduleName)",
                dependencies: ["AppFFI"],
                path: "Sources/\(naming.moduleName)"
            ),
            // Plain executable smoke harness: Xcode Command Line Tools ship
            // neither XCTest nor swift-testing, so `swift test` cannot run in the VM.
            .executableTarget(
                name: "FFIChecks",
                dependencies: ["AppFFI"],
                path: "Sources/FFIChecks"
            ),
        ]
    )
    """
  }

  public static func macosAppSwift(naming: RustProjectScaffold.MacOSNaming) -> String {
    """
    import AppFFI
    import SwiftUI

    @main
    struct \(naming.moduleName): App {
      var body: some Scene {
        WindowGroup("\(naming.displayName)") {
          ContentView()
        }
      }
    }

    /// Dumb SwiftUI binder: renders `UiSnapshot` and dispatches actions only.
    struct ContentView: View {
      @State private var label: String
      @State private var caption: String

      init() {
        let snap = uiInitialSnapshot()
        label = snap.label
        caption = snap.caption
      }

      var body: some View {
        VStack(spacing: 12) {
          Text(label)
            .accessibilityIdentifier("greeting.label")
          Text(caption)
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

  public static let macosBindingsPlaceholder = """
    // Placeholder so the AppFFI target exists on a fresh checkout.
    // `scripts/generate-bindings.sh` emits the real UniFFI-generated
    // `app_ffi.swift` into this directory (gitignored).
    """

  public static let macosFFIShim = """
    /* SwiftPM requires at least one source file per C target.
     * The real declarations come from the UniFFI-generated
     * `include/app_ffiFFI.h`, emitted by scripts/generate-bindings.sh. */
    """

  public static let macosFFIChecks = """
    import AppFFI
    import Foundation

    // FFI round-trip checks run as a plain executable because the VM toolchain
    // (Xcode Command Line Tools only) ships neither XCTest nor swift-testing.
    // Exits non-zero when a check breaks.

    func check(_ condition: Bool, _ message: String) {
      if !condition {
        fputs("FFIChecks FAILED: \\(message)\\n", stderr)
        exit(1)
      }
    }

    let snapshot = uiInitialSnapshot()
    check(
      snapshot.label == "hello, world!",
      "uiInitialSnapshot label mismatch: \\(snapshot.label)")
    check(
      snapshot.caption.contains("crates/ui"),
      "uiInitialSnapshot caption mismatch: \\(snapshot.caption)")

    let refreshed = uiDispatchRefresh()
    check(
      refreshed.label == "hello, world!",
      "uiDispatchRefresh label mismatch: \\(refreshed.label)")

    let greetingText = greeting(name: "compass")
    check(greetingText == "hello, compass", "greeting mismatch: \\(greetingText)")

    let request = GreetingRequest(name: "world", excited: true)
    do {
      let personalized = try personalizedGreeting(request: request)
      check(
        personalized == "hello, world!",
        "personalizedGreeting mismatch: \\(personalized)")
    } catch {
      fputs("FFIChecks FAILED: personalizedGreeting threw \\(error)\\n", stderr)
      exit(1)
    }

    print("FFIChecks ok: 4 checks passed")
    """

  public static func macosInfoPlist(naming: RustProjectScaffold.MacOSNaming) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleDisplayName</key>
        <string>\(naming.displayName)</string>
        <key>CFBundleExecutable</key>
        <string>\(naming.moduleName)</string>
        <key>CFBundleIdentifier</key>
        <string>\(naming.bundleIdentifier)</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>\(naming.moduleName)</string>
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
  }

  public static let swiftFormatConfig = """
    {
      "indentation": { "spaces": 2 },
      "lineLength": 100,
      "version": 1
    }
    """

  public static let generateBindingsScript = #"""
    #!/usr/bin/env bash
    # Regenerates the UniFFI Swift bindings and C header for apps/macos.
    # Builds the release staticlib that Package.swift links via Context.packageDirectory.
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

  public static func bundleMacOSScript(naming: RustProjectScaffold.MacOSNaming) -> String {
    #"""
    #!/usr/bin/env bash
    # Builds an ad-hoc signed \#(naming.moduleName).app under apps/macos/dist/.
    set -euo pipefail

    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    cd "$ROOT"

    bash "$ROOT/scripts/generate-bindings.sh"

    cd "$ROOT/apps/macos"
    swift build -c release

    APP="$ROOT/apps/macos/dist/\#(naming.moduleName).app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$ROOT/apps/macos/Info.plist" "$APP/Contents/Info.plist"
    cp "$ROOT/apps/macos/.build/release/\#(naming.moduleName)" \
      "$APP/Contents/MacOS/\#(naming.moduleName)"

    if command -v codesign >/dev/null 2>&1; then
      codesign --force --sign - "$APP"
    fi

    echo "bundled $APP"
    """#
  }

  public static func macosAXSmokeSwift(naming: RustProjectScaffold.MacOSNaming) -> String {
    #"""
    import AppKit
    import ApplicationServices
    import Foundation

    /// One-shot Accessibility smoke for \#(naming.moduleName). Finds the running app by
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
          return "AXIsProcessTrusted() is false; grant Accessibility to this helper in System Settings, or omit COMPASS_MACOS_UI_FIDELITY to skip headed fidelity."
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
      : "\#(naming.bundleIdentifier)"
    let expectedLabel = CommandLine.arguments.count > 2
      ? CommandLine.arguments[2]
      : "hello, world!"
    let expectedCaption = CommandLine.arguments.count > 3
      ? CommandLine.arguments[3]
      : "UI policy lives in crates/ui; this shell is SwiftUI only."
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
  }

  public static func macosUISmokeScript(naming: RustProjectScaffold.MacOSNaming) -> String {
    #"""
    #!/usr/bin/env bash
    # Opt-in headed fidelity: launch \#(naming.moduleName) in a GUI session, assert
    # Accessibility identifiers, and capture a screenshot for audit.
    # Enable with COMPASS_MACOS_UI_FIDELITY=1 (default off). Primary UI proof is
    # crates/ui simulation under `cargo test`.
    set -euo pipefail

    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    cd "$ROOT"

    fidelity="${COMPASS_MACOS_UI_FIDELITY:-0}"
    if [[ "$fidelity" != "1" && "$fidelity" != "true" && "$fidelity" != "yes" ]]; then
      echo "COMPASS_MACOS_UI_FIDELITY disabled; skipping headed UI fidelity (simulation is required via cargo test)"
      exit 0
    fi

    BUNDLE_ID="\#(naming.bundleIdentifier)"
    APP="$ROOT/apps/macos/dist/\#(naming.moduleName).app"
    SHOT="$ROOT/apps/macos/dist/ui-smoke.png"
    AX_SRC="$ROOT/scripts/macos-ax-smoke.swift"
    AX_BIN="$(mktemp -t macos-ax-smoke)"
    EXPECTED_LABEL="hello, world!"
    EXPECTED_CAPTION="UI policy lives in crates/ui; this shell is SwiftUI only."

    cleanup() {
      /usr/bin/killall "\#(naming.moduleName)" 2>/dev/null || true
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

    /usr/bin/killall "\#(naming.moduleName)" 2>/dev/null || true
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

    echo "macos ui fidelity ok ($SHOT)"
    """#
  }

  public static func verifyMacOSScript(naming: RustProjectScaffold.MacOSNaming) -> String {
    #"""
    #!/usr/bin/env bash
    # macOS product verify. Runs inside the embedded macOS VM: bindings +
    # swift build + FFIChecks executable. Headed launch + screenshot only when
    # COMPASS_MACOS_UI_FIDELITY=1. Primary UI proof is crates/ui simulation
    # under the standard Rust verify (`cargo test`).
    #
    # Uses `swift run FFIChecks` (not `swift test`): the VM has Command Line
    # Tools only, which do not ship XCTest / swift-testing.
    set -euo pipefail

    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    cd "$ROOT"

    if ! command -v swift >/dev/null 2>&1; then
      echo "macos product requires a Mac host/VM with the Swift toolchain (Xcode CLT)." >&2
      exit 1
    fi

    if [[ ! -f crates/ffi/Cargo.toml ]]; then
      echo "macos verify requires crates/ffi (UniFFI)." >&2
      exit 1
    fi
    if [[ ! -f crates/ui/Cargo.toml ]]; then
      echo "macos verify requires crates/ui (UI state / simulation)." >&2
      exit 1
    fi

    # Builds the Rust FFI crate (cdylib + staticlib) and regenerates bindings.
    bash "$ROOT/scripts/generate-bindings.sh"

    cd "$ROOT/apps/macos"
    swift build -c release
    # Compiles the generated UniFFI bindings and runs FFI round-trip checks.
    swift run -c release FFIChecks

    if xcrun -f swift-format >/dev/null 2>&1; then
      xcrun swift-format lint --strict --recursive \
        --configuration "$ROOT/.swift-format" \
        Sources/\#(naming.moduleName) Sources/FFIChecks
    elif command -v swift-format >/dev/null 2>&1; then
      swift-format lint --strict --recursive \
        --configuration "$ROOT/.swift-format" \
        Sources/\#(naming.moduleName) Sources/FFIChecks
    else
      echo "swift-format not found; skipping Swift lint"
    fi

    # Opt-in headed fidelity (default off).
    bash "$ROOT/scripts/macos-ui-smoke.sh"

    echo "macos verify ok"
    """#
  }
}
