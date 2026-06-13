import Darwin
import Foundation

package enum CompassEngineRuntimeError: LocalizedError, Equatable {
  case requestEncodingFailed
  case invalidUTF8Response
  case invalidResponse(String)
  case libraryNotFound(String)
  case symbolNotFound(String)
  case cargoBuildFailed(String)
  case engineFailed(String)

  package var errorDescription: String? {
    switch self {
    case .requestEncodingFailed:
      return "Compass engine request could not be encoded."
    case .invalidUTF8Response:
      return "Compass engine returned a non-UTF-8 response."
    case .invalidResponse(let detail):
      return "Compass engine returned an invalid response: \(detail)"
    case .libraryNotFound(let detail):
      return "Compass engine library was not found: \(detail)"
    case .symbolNotFound(let symbol):
      return "Compass engine symbol was not found: \(symbol)"
    case .cargoBuildFailed(let detail):
      return "Compass engine lazy build failed: \(detail)"
    case .engineFailed(let detail):
      return detail
    }
  }
}

package struct CompassEngineEnvelope: Decodable, Equatable {
  package var ok: Bool
  package var kind: String
  package var result: JSONFragment?
  package var message: String?
}

package struct JSONFragment: Codable, Equatable, Sendable {
  package var value: AnyJSONValue

  package init(value: AnyJSONValue) {
    self.value = value
  }

  package init(from decoder: Decoder) throws {
    value = try AnyJSONValue(from: decoder)
  }

  package func encode(to encoder: Encoder) throws {
    try value.encode(to: encoder)
  }

  package func data() throws -> Data {
    try JSONEncoder().encode(self)
  }

  package func string() throws -> String {
    String(decoding: try data(), as: UTF8.self)
  }
}

package indirect enum AnyJSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([AnyJSONValue])
  case object([String: AnyJSONValue])

  package init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([AnyJSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: AnyJSONValue].self))
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let values):
      try container.encode(values)
    case .object(let values):
      try container.encode(values)
    }
  }
}

package actor CompassEngineRuntime {
  package static let shared = CompassEngineRuntime()

  private typealias EngineFunction = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
  private typealias FreeFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

  private struct LoadedLibrary {
    var handle: UnsafeMutableRawPointer
    var verifyProject: EngineFunction
    var runEntrypoint: EngineFunction
    var freeString: FreeFunction
  }

  private var loadedLibrary: LoadedLibrary?

  package func verifyProject(root: URL) async throws -> CompassEngineEnvelope {
    let request = try requestData(["root": root.standardizedFileURL.path])
    return try await call(function: \.verifyProject, request: request)
  }

  package func runEntrypoint(
    root: URL,
    entrypoint: String,
    input: Data? = nil
  ) async throws -> CompassEngineEnvelope {
    var request: [String: Any] = [
      "root": root.standardizedFileURL.path,
      "entrypoint": entrypoint,
    ]
    if let input {
      request["input"] = try JSONSerialization.jsonObject(with: input)
    }
    return try await call(function: \.runEntrypoint, request: try requestData(request))
  }

  private func call(
    function: KeyPath<LoadedLibrary, EngineFunction>,
    request: Data
  ) async throws -> CompassEngineEnvelope {
    let library = try await loadLibrary()
    let response = try request.withUnsafeBytes { bytes -> String in
      let buffer = bytes.bindMemory(to: CChar.self)
      guard let baseAddress = buffer.baseAddress else {
        throw CompassEngineRuntimeError.requestEncodingFailed
      }
      guard let pointer = library[keyPath: function](baseAddress) else {
        throw CompassEngineRuntimeError.invalidResponse("null response pointer")
      }
      defer { library.freeString(pointer) }
      guard let response = String(validatingUTF8: pointer) else {
        throw CompassEngineRuntimeError.invalidUTF8Response
      }
      return response
    }
    let envelope: CompassEngineEnvelope
    do {
      envelope = try JSONDecoder().decode(CompassEngineEnvelope.self, from: Data(response.utf8))
    } catch {
      throw CompassEngineRuntimeError.invalidResponse(error.localizedDescription)
    }
    if !envelope.ok, envelope.result == nil {
      throw CompassEngineRuntimeError.engineFailed(envelope.message ?? "Compass engine failed.")
    }
    return envelope
  }

  private func loadLibrary() async throws -> LoadedLibrary {
    if let loadedLibrary {
      return loadedLibrary
    }
    let url = try await resolveLibraryURL()
    guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
      let message = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
      throw CompassEngineRuntimeError.libraryNotFound(message)
    }
    let library = try LoadedLibrary(
      handle: handle,
      verifyProject: loadSymbol("compass_engine_verify_project", handle: handle),
      runEntrypoint: loadSymbol("compass_engine_run_entrypoint", handle: handle),
      freeString: loadSymbol("compass_engine_free_string", handle: handle)
    )
    loadedLibrary = library
    return library
  }

  private func loadSymbol<T>(_ name: String, handle: UnsafeMutableRawPointer) throws -> T {
    guard let symbol = dlsym(handle, name) else {
      throw CompassEngineRuntimeError.symbolNotFound(name)
    }
    return unsafeBitCast(symbol, to: T.self)
  }

  private func resolveLibraryURL() async throws -> URL {
    if let raw = ProcessInfo.processInfo.environment["COMPASS_ENGINE_DYLIB"]?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    {
      let url = URL(fileURLWithPath: raw).standardizedFileURL
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
      throw CompassEngineRuntimeError.libraryNotFound(raw)
    }

    if let bundled = bundledLibraryURL() {
      return bundled
    }

    let devURL = devLibraryURL()
    if !FileManager.default.fileExists(atPath: devURL.path) || devLibraryNeedsBuild(devURL) {
      try await buildDevLibrary()
    }
    guard FileManager.default.fileExists(atPath: devURL.path) else {
      throw CompassEngineRuntimeError.libraryNotFound(devURL.path)
    }
    return devURL
  }

  private func bundledLibraryURL() -> URL? {
    for bundle in [Bundle.main, Bundle.module] {
      if let url = bundle.url(forResource: "libcompass_engine", withExtension: "dylib"),
        FileManager.default.fileExists(atPath: url.path)
      {
        return url
      }
    }
    return nil
  }

  private func buildDevLibrary() async throws {
    let manifest = repoRoot()
      .appending(path: "rust/compass-engine/Cargo.toml")
      .standardizedFileURL
    let result = try await ProcessRunner.runEnv(
      "cargo",
      ["build", "--manifest-path", manifest.path],
      workingDirectory: repoRoot(),
      timeout: 120
    )
    guard result.exitCode == 0 else {
      throw CompassEngineRuntimeError.cargoBuildFailed(
        [result.stdout, result.stderr]
          .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
          .joined(separator: "\n")
      )
    }
  }

  private func devLibraryURL() -> URL {
    repoRoot()
      .appending(path: "rust/compass-engine/target/debug/libcompass_engine.dylib")
      .standardizedFileURL
  }

  private func devLibraryNeedsBuild(_ libraryURL: URL) -> Bool {
    guard let libraryDate = modificationDate(for: libraryURL) else {
      return true
    }
    return devBuildInputURLs().contains { input in
      guard let inputDate = newestModificationDate(at: input) else { return false }
      return inputDate > libraryDate
    }
  }

  private func devBuildInputURLs() -> [URL] {
    let root = repoRoot()
    return [
      root.appending(path: "rust/compass-engine/Cargo.toml"),
      root.appending(path: "rust/compass-engine/src"),
      root.deletingLastPathComponent().appending(path: "Tessera/tessera-core/Cargo.toml"),
      root.deletingLastPathComponent().appending(path: "Tessera/tessera-core/src"),
    ]
  }

  private func newestModificationDate(at url: URL) -> Date? {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return nil
    }
    if !isDirectory.boolValue {
      return modificationDate(for: url)
    }
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else {
      return modificationDate(for: url)
    }
    var newest = modificationDate(for: url)
    for case let fileURL as URL in enumerator {
      guard ["rs", "toml"].contains(fileURL.pathExtension) else { continue }
      let values = try? fileURL.resourceValues(forKeys: Set(keys))
      guard values?.isRegularFile == true,
        let date = values?.contentModificationDate
      else { continue }
      if newest == nil || date > newest! {
        newest = date
      }
    }
    return newest
  }

  private func modificationDate(for url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .standardizedFileURL
  }

  private func requestData(_ object: [String: Any]) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    data.append(0)
    return data
  }
}

package enum CompassEngineProcess {
  package static func isStandardTesseraVerifyCommand(_ command: String) -> Bool {
    let normalized = command
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return normalized == "tessera verify . --json"
  }

  package static func shouldUseEmbeddedTessera(command: String, forgeProfile: ForgeProfile?) -> Bool {
    forgeProfile == .tesseraApp && isStandardTesseraVerifyCommand(command)
  }

  package static func verifyProject(root: URL) async throws -> ProcessResult {
    let envelope = try await CompassEngineRuntime.shared.verifyProject(root: root)
    let stdout = try envelope.result?.string() ?? "{}"
    let stderr = envelope.ok ? "" : envelope.message ?? tesseraFailureSummary(from: envelope.result)
    return ProcessResult(exitCode: envelope.ok ? 0 : 1, stdout: stdout, stderr: stderr)
  }

  package static func runEntrypoint(
    root: URL,
    entrypoint: String,
    input: Data? = nil
  ) async throws -> ProcessResult {
    let envelope = try await CompassEngineRuntime.shared.runEntrypoint(
      root: root,
      entrypoint: entrypoint,
      input: input
    )
    let stdout = try envelope.result?.string() ?? "{}"
    let stderr = envelope.ok ? "" : envelope.message ?? tesseraFailureSummary(from: envelope.result)
    return ProcessResult(exitCode: envelope.ok ? 0 : 1, stdout: stdout, stderr: stderr)
  }

  private static func tesseraFailureSummary(from result: JSONFragment?) -> String {
    guard let data = try? result?.data(),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return "Tessera verification failed."
    }
    if let failures = object["failures"] as? [[String: Any]], let failure = failures.first {
      return formatTesseraFailure(failure)
    }
    if let diagnostics = object["diagnostics"] as? [[String: Any]],
      let first = diagnostics.first,
      let message = first["message"] as? String
    {
      return message
    }
    if let tests = object["tests"] as? [[String: Any]] {
      for test in tests {
        guard let diagnostics = test["diagnostics"] as? [[String: Any]],
          let first = diagnostics.first,
          let message = first["message"] as? String
        else { continue }
        return message
      }
    }
    if let entrypoints = object["entrypoints"] as? [[String: Any]] {
      for entrypoint in entrypoints {
        guard let diagnostics = entrypoint["diagnostics"] as? [[String: Any]],
          let first = diagnostics.first,
          let message = first["message"] as? String
        else { continue }
        return message
      }
    }
    return "Tessera verification failed."
  }

  private static func formatTesseraFailure(_ failure: [String: Any]) -> String {
    let kind = (failure["kind"] as? String)?.replacingOccurrences(of: "_", with: " ")
      ?? "failure"
    let name = failure["name"] as? String
    let path = failure["path"] as? String
      ?? failure["source_path"] as? String
      ?? failure["context_path"] as? String
    let message = failure["message"] as? String ?? "Tessera verification failed."
    var summary = "Tessera \(kind)"
    if let name, !name.isEmpty {
      summary += " \(name)"
    }
    if let path, !path.isEmpty {
      summary += " at \(path)"
    }
    if let line = jsonInt(failure["line"]) {
      summary += ":\(line)"
      if let column = jsonInt(failure["column"]) {
        summary += ":\(column)"
      }
    }
    summary += ": \(message)"
    if let expected = jsonDescription(failure["expected_json"]),
      let actual = jsonDescription(failure["actual_json"])
    {
      summary += " (expected \(expected), got \(actual))"
    }
    return summary
  }

  private static func jsonInt(_ value: Any?) -> Int? {
    if let value = value as? Int {
      return value
    }
    if let value = value as? Double {
      return Int(value)
    }
    return nil
  }

  private static func jsonDescription(_ value: Any?) -> String? {
    guard let value, !(value is NSNull) else { return nil }
    if let value = value as? String {
      return #""\#(value)""#
    }
    if JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes])
    {
      return String(decoding: data, as: UTF8.self)
    }
    return String(describing: value)
  }
}
