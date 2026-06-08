import Foundation

enum CompassDaemonLocator {
  static let binaryName = "compassd"

  static func locateDaemonBinary(
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) -> URL? {
    for url in candidateURLs(bundle: bundle, fileManager: fileManager) {
      if fileManager.isExecutableFile(atPath: url.path) {
        return url.standardizedFileURL
      }
    }
    return nil
  }

  static func candidateURLs(
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) -> [URL] {
    var candidates: [URL] = []
    if let executableURL = bundle.executableURL {
      let macOSDirectory = executableURL.deletingLastPathComponent()
      candidates.append(macOSDirectory.appendingPathComponent(binaryName))
      candidates.append(
        macOSDirectory
          .deletingLastPathComponent()
          .appendingPathComponent("Resources", isDirectory: true)
          .appendingPathComponent(binaryName)
      )
    }
    candidates.append(bundle.bundleURL.appendingPathComponent("Contents/MacOS/\(binaryName)"))
    candidates.append(bundle.bundleURL.appendingPathComponent("Contents/Resources/\(binaryName)"))
    candidates.append(URL(fileURLWithPath: "/usr/local/bin/\(binaryName)"))

    let current = URL(fileURLWithPath: fileManager.currentDirectoryPath).standardizedFileURL
    candidates.append(contentsOf: devPathCandidates(startingAt: current))
    return unique(candidates)
  }

  private static func devPathCandidates(startingAt startURL: URL) -> [URL] {
    var urls: [URL] = []
    var current = startURL
    while true {
      urls.append(
        current
          .appendingPathComponent("target", isDirectory: true)
          .appendingPathComponent("release", isDirectory: true)
          .appendingPathComponent(binaryName)
      )
      urls.append(
        current
          .appendingPathComponent("target", isDirectory: true)
          .appendingPathComponent("debug", isDirectory: true)
          .appendingPathComponent(binaryName)
      )
      let parent = current.deletingLastPathComponent()
      if parent.path == current.path { break }
      current = parent
    }
    return urls
  }

  private static func unique(_ urls: [URL]) -> [URL] {
    var seen: Set<String> = []
    var result: [URL] = []
    for url in urls {
      let normalized = url.standardizedFileURL.path
      guard seen.insert(normalized).inserted else { continue }
      result.append(URL(fileURLWithPath: normalized))
    }
    return result
  }
}
