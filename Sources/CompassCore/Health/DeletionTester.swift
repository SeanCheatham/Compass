import Foundation

public enum DeletionProbeStatus: String, Codable, Equatable, Sendable {
  case proven
  case live
  case tangled
}

public struct DeletionProbeItem: Codable, Equatable, Sendable {
  public var candidate: DeadCodeCandidate
  public var status: DeletionProbeStatus
  public var detail: String

  public init(
    candidate: DeadCodeCandidate, status: DeletionProbeStatus, detail: String = ""
  ) {
    self.candidate = candidate
    self.status = status
    self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct DeletionProbeResult: Codable, Equatable, Sendable {
  public var items: [DeletionProbeItem]
  public var notes: [String]

  public init(items: [DeletionProbeItem] = [], notes: [String] = []) {
    self.items = items
    self.notes = notes
  }

  public var proven: [DeadCodeCandidate] {
    items.filter { $0.status == .proven }.map(\.candidate)
  }

  public var live: [DeadCodeCandidate] {
    items.filter { $0.status == .live }.map(\.candidate)
  }

  public var tangled: [DeletionProbeItem] {
    items.filter { $0.status == .tangled }
  }

  public func formattedForPrompt(maxItems: Int = 20) -> String {
    var lines: [String] = []
    let provenItems = proven
    if !provenItems.isEmpty {
      lines.append(
        "Proven cuts (deletion-tested: compiles + full suite green without these — prefer applying):"
      )
      for candidate in provenItems.prefix(maxItems) {
        lines.append("- \(candidate.shortLabel): \(candidate.message)")
      }
      if provenItems.count > maxItems {
        lines.append("_(+\(provenItems.count - maxItems) more proven)_")
      }
    }
    let tangledItems = tangled
    if !tangledItems.isEmpty {
      lines.append(
        "Tangled candidates (compile errors after cut — needs judgment; error tail included):"
      )
      for item in tangledItems.prefix(maxItems) {
        let tail = item.detail.isEmpty ? "" : " — \(String(item.detail.suffix(240)))"
        lines.append("- \(item.candidate.shortLabel)\(tail)")
      }
    }
    let liveItems = live
    if !liveItems.isEmpty {
      lines.append(
        "Live / suite-sensitive (compile ok but tests failed after cut — leave or strengthen tests):"
      )
      for candidate in liveItems.prefix(maxItems) {
        lines.append("- \(candidate.shortLabel)")
      }
    }
    if lines.isEmpty {
      return "_(no deletion-probe results)_"
    }
    return lines.joined(separator: "\n")
  }
}

/// Host-side span editor: delete line ranges and restore from in-memory originals.
public enum SpanEditor {
  /// Apply deletions; ranges are 1-indexed inclusive. Same-file ranges apply bottom-up.
  public static func applyDeletions(
    originals: [String: String],
    candidates: [DeadCodeCandidate]
  ) -> [String: String] {
    var byFile: [String: [DeadCodeCandidate]] = [:]
    for candidate in candidates {
      byFile[candidate.file, default: []].append(candidate)
    }
    var result = originals
    for (file, group) in byFile {
      guard var text = result[file] else { continue }
      let sorted = group.sorted { $0.startLine > $1.startLine }
      for candidate in sorted {
        text = deleteLines(in: text, startLine: candidate.startLine, endLine: candidate.endLine)
      }
      result[file] = text
    }
    return result
  }

  public static func deleteLines(in text: String, startLine: Int, endLine: Int) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let start = max(1, startLine)
    let end = min(lines.count, max(start, endLine))
    guard start <= lines.count else { return text }
    lines.removeSubrange((start - 1)..<end)
    return lines.joined(separator: "\n")
  }

  /// Pull additional unused-import / dead_code spans from a failing `cargo check` JSON stream.
  public static func expansionCandidates(
    from cargoJSON: String,
    excluding existing: [DeadCodeCandidate],
    maxNew: Int = 20
  ) -> [DeadCodeCandidate] {
    let parsed = DeadCodeCandidateParser.parse(cargoJSONLines: cargoJSON)
    let existingKeys = Set(
      existing.map { "\($0.file)|\($0.startLine)|\($0.endLine)" }
    )
    var added: [DeadCodeCandidate] = []
    for candidate in parsed where added.count < maxNew {
      let key = "\(candidate.file)|\(candidate.startLine)|\(candidate.endLine)"
      guard !existingKeys.contains(key) else { continue }
      // Prefer cheap single-line unused_imports when expanding.
      if candidate.lint == "unused_imports" || candidate.lineCount <= 3 {
        added.append(candidate)
      }
    }
    return added
  }
}

/// Deletion testing: cut candidates, grow until compile, re-run tests, always revert.
public enum DeletionTester {
  public static let maxCandidates = 40
  public static let maxExpansionIterations = 5
  public static let maxExtraLines = 80

  public static func probe(
    repoURL: URL,
    candidates: [DeadCodeCandidate],
    bashRunner: AgentBashRunner,
    timeout: TimeInterval,
    onLive: (@Sendable (LiveEvent) -> Void)? = nil
  ) async -> DeletionProbeResult {
    let capped = Array(candidates.prefix(maxCandidates))
    guard !capped.isEmpty else {
      return DeletionProbeResult(notes: ["no dead-code candidates to probe"])
    }

    var notes: [String] = []
    if candidates.count > maxCandidates {
      notes.append("capped deletion probe to \(maxCandidates) of \(candidates.count) candidates")
    }

    let originals = loadOriginals(repoURL: repoURL, candidates: capped)
    guard !originals.isEmpty else {
      return DeletionProbeResult(notes: ["could not read candidate source files"])
    }

    onLive?(
      LiveEvent(
        level: .info,
        text: "Deletion probe",
        detail: "Probing \(capped.count) candidate(s)",
        kind: .message,
        status: .running,
        metadata: ["phase": AgentPhase.health.rawValue]
      )
    )

    defer { restore(repoURL: repoURL, originals: originals) }

    // First try the full batch with expansion.
    let full = await evaluateBatch(
      repoURL: repoURL,
      originals: originals,
      batch: capped,
      bashRunner: bashRunner,
      timeout: timeout,
      onLive: onLive
    )
    switch full.outcome {
    case .proven:
      notes.append(contentsOf: full.notes)
      return DeletionProbeResult(
        items: capped.map { DeletionProbeItem(candidate: $0, status: .proven) },
        notes: notes
      )
    case .live(let detail):
      notes.append(contentsOf: full.notes)
      return DeletionProbeResult(
        items: capped.map {
          DeletionProbeItem(candidate: $0, status: .live, detail: detail)
        },
        notes: notes
      )
    case .compileFailed(let detail):
      notes.append(contentsOf: full.notes)
      // One split level: try each half independently.
      if capped.count <= 1 {
        return DeletionProbeResult(
          items: [
            DeletionProbeItem(candidate: capped[0], status: .tangled, detail: detail)
          ],
          notes: notes
        )
      }
      let mid = capped.count / 2
      let left = Array(capped[..<mid])
      let right = Array(capped[mid...])
      var items: [DeletionProbeItem] = []
      for half in [left, right] {
        restore(repoURL: repoURL, originals: originals)
        let halfResult = await evaluateBatch(
          repoURL: repoURL,
          originals: originals,
          batch: half,
          bashRunner: bashRunner,
          timeout: timeout,
          onLive: onLive
        )
        notes.append(contentsOf: halfResult.notes)
        switch halfResult.outcome {
        case .proven:
          items.append(contentsOf: half.map {
            DeletionProbeItem(candidate: $0, status: .proven)
          })
        case .live(let d):
          items.append(contentsOf: half.map {
            DeletionProbeItem(candidate: $0, status: .live, detail: d)
          })
        case .compileFailed(let d):
          items.append(contentsOf: half.map {
            DeletionProbeItem(candidate: $0, status: .tangled, detail: d)
          })
        }
      }
      return DeletionProbeResult(items: items, notes: notes)
    }
  }

  private enum BatchOutcome {
    case proven
    case live(String)
    case compileFailed(String)
  }

  private struct BatchEval {
    var outcome: BatchOutcome
    var notes: [String]
  }

  private static func evaluateBatch(
    repoURL: URL,
    originals: [String: String],
    batch: [DeadCodeCandidate],
    bashRunner: AgentBashRunner,
    timeout: TimeInterval,
    onLive: (@Sendable (LiveEvent) -> Void)?
  ) async -> BatchEval {
    var working = batch
    var extraLines = 0
    var notes: [String] = []

    for iteration in 0..<maxExpansionIterations {
      restore(repoURL: repoURL, originals: originals)
      let edited = SpanEditor.applyDeletions(originals: originals, candidates: working)
      writeFiles(repoURL: repoURL, contents: edited)

      let check = await runBash(
        command: DeadCodeCandidateParser.checkCommand,
        label: "deletion probe check (iter \(iteration))",
        repoURL: repoURL,
        bashRunner: bashRunner,
        timeout: min(timeout, 180),
        onLive: onLive
      )
      let checkOut = (check?.stdout ?? "") + "\n" + (check?.stderr ?? "")
      if check?.exitCode == 0 {
        let testCommand =
          "cargo test --workspace -- --nocapture 2>&1 | tee /tmp/compass-deletion-test.log | tail -c 80000"
        let test = await runBash(
          command: testCommand,
          label: "deletion probe test",
          repoURL: repoURL,
          bashRunner: bashRunner,
          timeout: timeout,
          onLive: onLive
        )
        if test?.exitCode == 0 {
          if working.count > batch.count {
            notes.append(
              "expanded cut by \(working.count - batch.count) dangling span(s) to restore compile"
            )
          }
          return BatchEval(outcome: .proven, notes: notes)
        }
        let detail = String(((test?.stdout ?? "") + (test?.stderr ?? "")).suffix(2000))
        return BatchEval(outcome: .live(detail), notes: notes)
      }

      // Expand with newly unused imports / small dead spans.
      let expansion = SpanEditor.expansionCandidates(
        from: checkOut,
        excluding: working,
        maxNew: 12
      )
      let affordable = expansion.filter { candidate in
        let next = extraLines + candidate.lineCount
        return next <= maxExtraLines
      }
      if affordable.isEmpty {
        let detail = String(checkOut.suffix(2000))
        return BatchEval(outcome: .compileFailed(detail), notes: notes)
      }
      for candidate in affordable {
        extraLines += candidate.lineCount
      }
      working.append(contentsOf: affordable)
      notes.append(
        "expansion iter \(iteration): +\(affordable.count) span(s) (\(extraLines) extra lines)"
      )
    }

    return BatchEval(
      outcome: .compileFailed("expansion exhausted after \(maxExpansionIterations) iterations"),
      notes: notes
    )
  }

  private static func loadOriginals(
    repoURL: URL,
    candidates: [DeadCodeCandidate]
  ) -> [String: String] {
    var originals: [String: String] = [:]
    for file in Set(candidates.map(\.file)) {
      let url = repoURL.appending(path: file)
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
      originals[file] = text
    }
    return originals
  }

  private static func writeFiles(repoURL: URL, contents: [String: String]) {
    for (file, text) in contents {
      let url = repoURL.appending(path: file)
      try? text.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  public static func restore(repoURL: URL, originals: [String: String]) {
    writeFiles(repoURL: repoURL, contents: originals)
  }

  private static func runBash(
    command: String,
    label: String,
    repoURL: URL,
    bashRunner: AgentBashRunner,
    timeout: TimeInterval,
    onLive: (@Sendable (LiveEvent) -> Void)?
  ) async -> ProcessResult? {
    let correlationID = UUID().uuidString
    let timeoutMs = Int(timeout * 1000)
    onLive?(
      LiveEvent(
        level: .raw,
        text: label,
        detail: "\(command) (macOS VM, timeout \(timeoutMs)ms)",
        kind: .command,
        status: .running,
        correlationID: correlationID,
        metadata: [
          "tool": "bash",
          "command": command,
          "timeoutMs": "\(timeoutMs)",
          "phase": AgentPhase.health.rawValue,
        ],
        payload: .bash(
          command: command,
          cwd: "/workspace",
          output: nil,
          isError: nil
        )
      )
    )
    do {
      let result = try await bashRunner.run(
        command: command,
        workingDirectory: repoURL,
        timeout: timeout
      )
      let failed = result.exitCode != 0
      let combined = result.stdout + result.stderr
      onLive?(
        LiveEvent(
          level: failed ? .error : .success,
          text: label,
          detail: failed
            ? "exit \(result.exitCode)\n\(String(combined.suffix(1500)))"
            : "exit 0",
          kind: .command,
          status: failed ? .failed : .completed,
          correlationID: correlationID,
          metadata: [
            "tool": "bash",
            "command": command,
            "exitCode": "\(result.exitCode)",
            "isError": failed ? "true" : "false",
            "phase": AgentPhase.health.rawValue,
          ],
          payload: .bash(
            command: command,
            cwd: "/workspace",
            output: String(combined.suffix(AgentExecutor.payloadMaxTerminalBytes)),
            isError: failed
          )
        )
      )
      return result
    } catch {
      onLive?(
        LiveEvent(
          level: .error,
          text: label,
          detail: error.localizedDescription,
          kind: .command,
          status: .failed,
          correlationID: correlationID,
          metadata: [
            "tool": "bash",
            "command": command,
            "isError": "true",
            "phase": AgentPhase.health.rawValue,
          ],
          payload: .bash(
            command: command,
            cwd: "/workspace",
            output: error.localizedDescription,
            isError: true
          )
        )
      )
      return nil
    }
  }
}
