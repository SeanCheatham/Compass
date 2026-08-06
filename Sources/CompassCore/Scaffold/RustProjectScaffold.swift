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

  /// Stable identifiers derived from the display project name for SPM / bundle / process names.
  public struct MacOSNaming: Equatable, Sendable {
    public var displayName: String
    public var moduleName: String
    public var bundleIdentifier: String

    public init(projectName: String) {
      let display = Options(projectName: projectName).projectName
      self.displayName = display
      self.moduleName = Self.swiftTypeName(from: display)
      self.bundleIdentifier = "com.compass.generated.\(moduleName.lowercased())"
    }

    /// PascalCase Swift type / executable target name (`My Factory App` → `MyFactoryApp`).
    /// Already-valid identifiers like `CompassRustApp5` are preserved.
    public static func swiftTypeName(from raw: String) -> String {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.range(of: #"^[A-Za-z][A-Za-z0-9]*$"#, options: .regularExpression) != nil {
        if let first = trimmed.first, first.isLowercase {
          return String(first).uppercased() + trimmed.dropFirst()
        }
        return String(trimmed)
      }
      let parts =
        trimmed
        .split { !$0.isLetter && !$0.isNumber }
        .map { part -> String in
          let lower = part.lowercased()
          guard let first = lower.first else { return "" }
          return String(first).uppercased() + lower.dropFirst()
        }
        .filter { !$0.isEmpty }
      var name = parts.joined()
      if name.isEmpty { name = "CompassApp" }
      if let first = name.first, first.isNumber {
        name = "App" + name
      }
      return name
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
    let hasServer = GeneratedProducts.contains(products, .server)

    var files: [ScaffoldFile] = [
      ScaffoldFile(
        path: ".gitignore",
        contents: RustScaffoldCoreTemplates.gitignore(hasMacOS: hasMacOS)
      ),
      ScaffoldFile(
        path: "Cargo.toml",
        contents: RustScaffoldCoreTemplates.workspaceManifest(
          hasCLI: hasCLI, hasMacOS: hasMacOS, hasServer: hasServer)
      ),
      ScaffoldFile(path: "rust-toolchain.toml", contents: RustScaffoldCoreTemplates.rustToolchain),
      ScaffoldFile(
        path: "README.md",
        contents: RustScaffoldCoreTemplates.readme(
          projectName: name, hasCLI: hasCLI, hasMacOS: hasMacOS, hasServer: hasServer)
      ),
      ScaffoldFile(path: "crates/core/Cargo.toml", contents: RustScaffoldCoreTemplates.coreManifest),
      ScaffoldFile(path: "crates/core/src/lib.rs", contents: RustScaffoldCoreTemplates.coreLib),
    ]

    if hasCLI {
      files.append(contentsOf: [
        ScaffoldFile(path: "crates/cli/Cargo.toml", contents: RustScaffoldCLITemplates.cliManifest),
        ScaffoldFile(path: "crates/cli/src/main.rs", contents: RustScaffoldCLITemplates.cliMain),
        ScaffoldFile(path: "crates/cli/tests/cli.rs", contents: RustScaffoldCLITemplates.cliSmokeTest),
      ])
    }

    if hasServer {
      files.append(contentsOf: [
        ScaffoldFile(
          path: "crates/server/Cargo.toml", contents: RustScaffoldServerTemplates.serverManifest),
        ScaffoldFile(
          path: "crates/server/src/main.rs", contents: RustScaffoldServerTemplates.serverMain),
        ScaffoldFile(
          path: "crates/server/src/lib.rs", contents: RustScaffoldServerTemplates.serverLib),
        ScaffoldFile(
          path: "crates/server/tests/http.rs", contents: RustScaffoldServerTemplates.httpIntegrationTest),
      ])
    }

    if hasMacOS {
      let naming = MacOSNaming(projectName: name)
      let m = RustScaffoldMacOSTemplates.self
      files.append(contentsOf: [
        ScaffoldFile(path: ".swift-format", contents: m.swiftFormatConfig),
        ScaffoldFile(path: "crates/ui/Cargo.toml", contents: m.uiManifest),
        ScaffoldFile(path: "crates/ui/src/lib.rs", contents: m.uiLib),
        ScaffoldFile(path: "crates/ffi/Cargo.toml", contents: m.ffiManifest),
        ScaffoldFile(path: "crates/ffi/src/lib.rs", contents: m.ffiLib),
        ScaffoldFile(path: "crates/ffi/src/bin/uniffi-bindgen.rs", contents: m.ffiBindgenMain),
        ScaffoldFile(path: "apps/macos/Package.swift", contents: m.macosPackageSwift(naming: naming)),
        ScaffoldFile(
          path: "apps/macos/Sources/\(naming.moduleName)/\(naming.moduleName).swift",
          contents: m.macosAppSwift(naming: naming)
        ),
        ScaffoldFile(
          path: "apps/macos/Sources/AppFFI/Placeholder.swift",
          contents: m.macosBindingsPlaceholder
        ),
        ScaffoldFile(path: "apps/macos/Sources/app_ffiFFI/shim.c", contents: m.macosFFIShim),
        ScaffoldFile(path: "apps/macos/Sources/app_ffiFFI/include/.gitkeep", contents: ""),
        ScaffoldFile(path: "apps/macos/Sources/FFIChecks/main.swift", contents: m.macosFFIChecks),
        ScaffoldFile(path: "apps/macos/Info.plist", contents: m.macosInfoPlist(naming: naming)),
        ScaffoldFile(path: "scripts/generate-bindings.sh", contents: m.generateBindingsScript),
        ScaffoldFile(path: "scripts/bundle-macos.sh", contents: m.bundleMacOSScript(naming: naming)),
        ScaffoldFile(
          path: "scripts/macos-ax-smoke.swift", contents: m.macosAXSmokeSwift(naming: naming)),
        ScaffoldFile(
          path: "scripts/macos-ui-smoke.sh", contents: m.macosUISmokeScript(naming: naming)),
        ScaffoldFile(
          path: "scripts/verify-macos.sh", contents: m.verifyMacOSScript(naming: naming)),
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
    let hasServer = fm.fileExists(atPath: url.appending(path: "crates/server/Cargo.toml").path)
    let hasMacOS =
      fm.fileExists(atPath: url.appending(path: "apps/macos/Package.swift").path)
      || fm.fileExists(atPath: url.appending(path: "crates/ffi/Cargo.toml").path)
      || fm.fileExists(atPath: url.appending(path: "crates/ui/Cargo.toml").path)
    return hasCLI || hasServer || hasMacOS
  }
}
