import Foundation

enum TesseraProjectScaffold {
  struct Options: Equatable, Sendable {
    var projectName: String

    init(projectName: String) {
      self.projectName = Self.packageName(projectName)
    }

    private static func packageName(_ raw: String) -> String {
      let normalized =
        raw
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9._-]+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
      return normalized.isEmpty ? "compass-tessera-app" : normalized
    }
  }

  struct ScaffoldFile: Equatable, Sendable {
    var path: String
    var contents: String
  }

  static func files(options: Options) -> [ScaffoldFile] {
    let name = options.projectName
    return [
      ScaffoldFile(path: "tessera.json", contents: manifest(projectName: name)),
      ScaffoldFile(path: ".gitignore", contents: gitignore),
      ScaffoldFile(path: "README.md", contents: readme(projectName: name)),
      ScaffoldFile(path: "src/display-name.tes", contents: displayNameSource),
      ScaffoldFile(path: "contexts/user.json", contents: userContext(projectName: name)),
      ScaffoldFile(path: "tests/display-name.json", contents: displayNameTest(projectName: name)),
    ]
  }

  static func write(to url: URL, options: Options) throws {
    let fm = FileManager.default
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
    return fm.fileExists(atPath: url.appending(path: "tessera.json").path)
      && fm.fileExists(atPath: url.appending(path: "src/display-name.tes").path)
      && fm.fileExists(atPath: url.appending(path: "tests/display-name.json").path)
  }

  private static let gitignore = """
    target/
    .DS_Store
    *.log
    """

  private static func readme(projectName: String) -> String {
    """
    # \(projectName)

    A Compass-generated Tessera app workspace.

    ## Commands

    - `tessera verify . --json`
    - `tessera app cli --json`
    - `tessera app web --json`
    """
  }

  private static func manifest(projectName: String) -> String {
    """
    {
      "name": "\(projectName)",
      "version": "0.1.0",
      "capabilities": ["cli", "web-json"],
      "entrypoints": {
        "cli": {
          "source": "display-name",
          "context": "user",
          "expect": "Text",
          "kind": "cli"
        },
        "web": {
          "source": "display-name",
          "context": "user",
          "expect": "Text",
          "kind": "web-json"
        }
      }
    }
    """
  }

  private static let displayNameSource = """
    ; Returns a display label for the current user.
    (def display ((name Text)) (concat name "!"))
    (display user.name)
    """

  private static func userContext(projectName: String) -> String {
    """
    {
      "user": {
        "name": "\(projectName)"
      },
      "args": ["preview"]
    }
    """
  }

  private static func displayNameTest(projectName: String) -> String {
    """
    {
      "name": "display-name",
      "source": "display-name",
      "context": "user",
      "expect": "\(projectName)!"
    }
    """
  }
}
