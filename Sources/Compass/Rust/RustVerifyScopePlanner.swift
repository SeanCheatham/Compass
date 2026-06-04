import Foundation

struct RustVerifyScopeSuggestion: Equatable, Sendable {
  var command: String
  var reason: String
  var needsVisualVerify: Bool
}

enum RustVerifyScopePlanner {
  static func suggest(
    changedFiles: [String],
    graph: CargoGraphSnapshot?
  ) -> RustVerifyScopeSuggestion {
    let files = changedFiles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard !files.isEmpty else {
      return .init(
        command: "cargo test --workspace --all-features",
        reason: "No changed files were available, so use the full Rust workspace test command.",
        needsVisualVerify: false
      )
    }
    if files.contains(where: { $0 == "Cargo.toml" || $0 == "Cargo.lock" }) {
      return full(reason: "Root Cargo manifest or lockfile changed.")
    }
    if files.contains(where: { $0.hasPrefix("schemas/") }) {
      return .init(
        command: "cargo test -p app-core --all-features",
        reason: "Schema changes should at least verify app-core state/schema tests.",
        needsVisualVerify: false
      )
    }
    let affected = affectedPackages(files: files, graph: graph)
    let visual = files.contains { $0.hasPrefix("crates/app-desktop/") || $0.contains("egui") }
    if affected.count == 1, let package = affected.first {
      return .init(
        command: "cargo test -p \(package) --all-features",
        reason: "Only \(package) paths changed.",
        needsVisualVerify: visual
      )
    }
    return full(reason: "Multiple crates or workspace-level files changed.", needsVisualVerify: visual)
  }

  private static func full(reason: String, needsVisualVerify: Bool = false) -> RustVerifyScopeSuggestion {
    .init(command: "cargo test --workspace --all-features", reason: reason, needsVisualVerify: needsVisualVerify)
  }

  private static func affectedPackages(files: [String], graph: CargoGraphSnapshot?) -> Set<String> {
    guard let graph else { return [] }
    var packages = Set<String>()
    for member in graph.graph.members {
      let prefix = member.packageDir.hasSuffix("/") ? member.packageDir : member.packageDir + "/"
      if files.contains(where: { $0.hasPrefix(prefix) || $0 == member.manifestPath }) {
        packages.insert(member.name)
      }
    }
    return packages
  }
}
