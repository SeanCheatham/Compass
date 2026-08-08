import Foundation

extension Prompts {
  /// Phase output schemas live as standalone `.json` files under
  /// `Resources/Schemas/`. They are loaded once on first access and
  /// cached for the lifetime of the process. If a schema is missing or
  /// malformed, this trips a `fatalError` at first read rather than
  /// silently shipping a broken phase. Schemas are validated as JSON at
  /// load time so a hand-edit that breaks syntax is caught immediately.
  public static let planSchema = loadSchema("plan")
  public static let developSchema = loadSchema("develop")
  public static let criticSchema = loadSchema("critic")
  public static let requirementsAuditSchema = loadSchema("requirements_audit")
  public static let healthSchema = loadSchema("health")
  public static let subAgentSchema = loadSchema("subAgent")

  /// Token type used to anchor `Bundle(for:)` lookups in the Xcode-built
  /// app bundle. `Bundle.module` is only synthesized by SwiftPM, so the
  /// Xcode target reaches its resources through this class instead.
  private final class SchemaBundleToken {}

  private static func loadSchema(_ name: String) -> String {
    let bundle = schemaBundle()
    // Both SwiftPM (`.process("Resources")`) and Xcode's filesystem-
    // synchronized resource phase flatten the `Resources/Schemas/`
    // tree into the bundle's resource root, so look up by filename
    // without a subdirectory hint.
    guard
      let url = bundle.url(forResource: name, withExtension: "json")
    else {
      fatalError(
        "Missing schema resource: \(name).json (bundle: \(bundle.bundleURL.path))")
    }
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      fatalError("Cannot read schema \(name).json: \(error)")
    }
    do {
      _ = try JSONSerialization.jsonObject(with: data)
    } catch {
      fatalError("Schema \(name).json is not valid JSON: \(error)")
    }
    return String(decoding: data, as: UTF8.self)
  }

  /// `Bundle.module` exists under SwiftPM (`swift build`/`swift test`)
  /// but not under the Xcode app target, which builds the source tree
  /// directly. Pick the right one via the `SWIFT_PACKAGE` compiler flag.
  private static func schemaBundle() -> Bundle {
    #if SWIFT_PACKAGE
      return Bundle.module
    #else
      return Bundle(for: SchemaBundleToken.self)
    #endif
  }
}
