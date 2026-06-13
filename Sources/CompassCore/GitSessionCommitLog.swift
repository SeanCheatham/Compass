import Foundation

package enum GitSessionCommitLog {
  package static func commits(in repoURL: URL, from before: String?, to after: String?) async
    -> [SessionCommit]
  {
    guard let after, before != after else { return [] }
    let range = before.map { "\($0)..\(after)" } ?? after
    guard
      let result = try? await ProcessRunner.runEnv(
        "git",
        ["log", "--reverse", "--format=%H%x09%h%x09%s", range],
        workingDirectory: repoURL,
        timeout: 10
      ),
      result.exitCode == 0
    else {
      return []
    }

    return result.stdout
      .split(whereSeparator: \.isNewline)
      .compactMap { line in
        let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        return SessionCommit(sha: parts[0], short: parts[1], subject: parts[2])
      }
  }
}
