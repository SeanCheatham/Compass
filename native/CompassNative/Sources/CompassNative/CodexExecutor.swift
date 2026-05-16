import Foundation

struct CodexRunConfiguration {
    var codexBinary: String
    var repoURL: URL
    var sandbox: String
    var model: String?
    var schema: String
    var prompt: String
}

final class CodexExecutor {
    private var process: Process?

    func cancel() {
        process?.terminate()
    }

    func run<T: Decodable>(
        _ configuration: CodexRunConfiguration,
        decode type: T.Type,
        onEvent: @escaping (LiveEvent) -> Void
    ) async throws -> T {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "CompassNative-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let schemaURL = tempDirectory.appending(path: "schema.json")
        let outputURL = tempDirectory.appending(path: "last-message.json")
        let promptURL = tempDirectory.appending(path: "prompt.txt")
        try configuration.schema.write(to: schemaURL, atomically: true, encoding: .utf8)
        try configuration.prompt.write(to: promptURL, atomically: true, encoding: .utf8)

        var arguments = [
            "exec",
            "--cd", configuration.repoURL.path,
            "--sandbox", configuration.sandbox,
            "-c", "approval_policy=\"never\"",
            "--json",
            "--output-schema", schemaURL.path,
            "--output-last-message", outputURL.path
        ]

        if let model = configuration.model?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            arguments += ["--model", model]
        }

        arguments.append("-")

        let result = try await runCodex(
            binary: configuration.codexBinary,
            arguments: arguments,
            workingDirectory: configuration.repoURL,
            inputFile: promptURL,
            onEvent: onEvent
        )

        guard result.exitCode == 0 else {
            throw CodexRunError.nonZeroExit(
                code: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let data = try Data(contentsOf: outputURL)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let text = String(decoding: data, as: UTF8.self)
            throw CodexRunError.decodeFailed(message: error.localizedDescription, body: text)
        }
    }

    private func runCodex(
        binary: String,
        arguments: [String],
        workingDirectory: URL,
        inputFile: URL,
        onEvent: @escaping (LiveEvent) -> Void
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            if binary.contains("/") {
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [binary] + arguments
            }
            process.currentDirectoryURL = workingDirectory
            process.environment = Self.processEnvironment()

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            let inputHandle: FileHandle
            do {
                inputHandle = try FileHandle(forReadingFrom: inputFile)
            } catch {
                continuation.resume(throwing: error)
                return
            }
            process.standardInput = inputHandle

            let outputStore = CodexOutputStore()

            let finish: @Sendable (Result<ProcessResult, Error>) -> Void = { result in
                guard outputStore.claimFinish() else { return }
                let remainder = outputStore.takePendingRemainder()
                if !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onEvent(Self.renderJSONLine(remainder))
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                try? inputHandle.close()
                self.process = nil
                continuation.resume(with: result)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in outputStore.appendStdout(chunk) {
                    onEvent(Self.renderJSONLine(line))
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                outputStore.appendStderr(chunk)
                onEvent(LiveEvent(
                    level: .warning,
                    text: "Codex diagnostic",
                    detail: chunk.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: .message
                ))
            }

            process.terminationHandler = { process in
                let snapshot = outputStore.snapshot()
                finish(.success(ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: snapshot.stdout,
                    stderr: snapshot.stderr
                )))
            }

            do {
                try process.run()
                self.process = process
            } catch {
                finish(.failure(error))
            }
        }
    }

    private static func renderJSONLine(_ line: String) -> LiveEvent {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LiveEvent(level: .raw, text: trimmedLine, kind: .message)
        }

        let type = object["type"] as? String ?? "event"
        if let item = object["item"] as? [String: Any],
           let itemType = item["type"] as? String {
            let status = status(for: type, item: item)
            let correlationID = (item["id"] as? String) ?? fallbackCorrelationID(for: item)
            switch itemType {
            case "command_execution":
                let command = item["command"] as? String ?? "(command)"
                let displayCommand = cleanShellCommand(command)
                let exitCode = item["exit_code"] as? Int
                let title: String
                if let exitCode, exitCode != 0 {
                    title = "Command failed"
                } else if status == .running {
                    title = "Running command"
                } else if status == .completed {
                    title = "Command completed"
                } else {
                    title = "Command"
                }
                let detail = exitCode.map { "\(displayCommand)\nexit code \($0)" } ?? displayCommand
                return LiveEvent(
                    level: exitCode.map { $0 == 0 ? .success : .error } ?? (status == .completed ? .success : .raw),
                    text: title,
                    detail: detail,
                    kind: .command,
                    status: exitCode.map { $0 == 0 ? .completed : .failed } ?? status,
                    correlationID: correlationID
                )
            case "agent_message":
                let text = item["text"] as? String ?? ""
                var event = summarizeAgentMessage(text, eventType: type)
                event.status = status == .running ? .running : .completed
                event.correlationID = correlationID
                return event
            case "file_change":
                return LiveEvent(
                    level: status == .completed ? .success : .raw,
                    text: status == .running ? "Preparing file changes" : "File changes ready",
                    kind: .fileChange,
                    status: status,
                    correlationID: correlationID
                )
            default:
                return LiveEvent(
                    level: .raw,
                    text: readableEventType(itemType),
                    detail: readableEventType(type),
                    kind: .lifecycle,
                    status: status,
                    correlationID: correlationID
                )
            }
        }

        if let message = object["message"] as? String {
            return LiveEvent(
                level: .info,
                text: readableEventType(type),
                detail: message,
                kind: .message
            )
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return LiveEvent(
                level: .error,
                text: readableEventType(type),
                detail: message,
                kind: .message,
                status: .failed
            )
        }
        return LiveEvent(
            level: .raw,
            text: readableEventType(type),
            kind: .lifecycle,
            status: lifecycleStatus(for: type)
        )
    }

    private static func summarizeAgentMessage(_ text: String, eventType: String) -> LiveEvent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LiveEvent(level: .raw, text: "Codex message", kind: .agentMessage)
        }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let completed = object["completed"] as? [Any],
               object.keys.contains("immediate"),
               object.keys.contains("midTerm"),
               object.keys.contains("longTerm") {
                let immediate = object["immediate"] as? [String: Any]
                let plan = firstLine(immediate?["plan"] as? String) ?? "none"
                let verify = firstLine(immediate?["verify"] as? String) ?? "none"
                return LiveEvent(
                    level: .raw,
                    text: "Candidate plan state",
                    detail: "Not accepted yet\nCompleted: \(completed.count)\nImmediate: \(plan)\nVerify: \(verify)",
                    kind: .agentMessage,
                    status: .completed
                )
            }

            if let status = object["status"] as? String,
               object.keys.contains("summary"),
               object.keys.contains("feedback") {
                let summary = firstLine(object["summary"] as? String) ?? ""
                return LiveEvent(
                    level: .raw,
                    text: "Candidate develop summary",
                    detail: "Not accepted yet\nStatus: \(status)\nSummary: \(summary)",
                    kind: .agentMessage,
                    status: .completed
                )
            }

            if let summary = object["summary"] as? String,
               object.keys.contains("state") {
                return LiveEvent(
                    level: .raw,
                    text: "Reflection summary",
                    detail: summary,
                    kind: .agentMessage,
                    status: .completed
                )
            }
        }

        return LiveEvent(
            level: .raw,
            text: "Codex response",
            detail: trimmed,
            kind: .agentMessage,
            status: .completed
        )
    }

    private static func firstLine(_ text: String?) -> String? {
        text?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
    }

    private static func status(for eventType: String, item: [String: Any]) -> LiveLine.Status {
        if let exitCode = item["exit_code"] as? Int {
            return exitCode == 0 ? .completed : .failed
        }
        switch eventType {
        case "item.started":
            return .running
        case "item.completed":
            return .completed
        default:
            return .none
        }
    }

    private static func lifecycleStatus(for eventType: String) -> LiveLine.Status {
        switch eventType {
        case let type where type.hasSuffix(".started"):
            return .running
        case let type where type.hasSuffix(".completed"):
            return .completed
        case let type where type.hasSuffix(".failed"):
            return .failed
        default:
            return .none
        }
    }

    private static func fallbackCorrelationID(for item: [String: Any]) -> String? {
        if let command = item["command"] as? String {
            return "command:\(command)"
        }
        if let text = item["text"] as? String {
            return "message:\(text.hashValue)"
        }
        return nil
    }

    private static func cleanShellCommand(_ command: String) -> String {
        let zshPrefix = "/bin/zsh -lc "
        let shPrefix = "/bin/sh -lc "
        let raw: String
        if command.hasPrefix(zshPrefix) {
            raw = String(command.dropFirst(zshPrefix.count))
        } else if command.hasPrefix(shPrefix) {
            raw = String(command.dropFirst(shPrefix.count))
        } else {
            raw = command
        }

        return unquoteShellArgument(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unquoteShellArgument(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.first == "'", value.last == "'" {
            let inner = value.dropFirst().dropLast()
            return inner.replacingOccurrences(of: "'\\''", with: "'")
        }
        if value.first == "\"", value.last == "\"" {
            let inner = value.dropFirst().dropLast()
            return inner.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return value
    }

    private static func readableEventType(_ type: String) -> String {
        type
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let pathAdditions = [
            "/Applications/Codex.app/Contents/Resources",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingPath = environment["PATH"] ?? ""
        let mergedPath = (pathAdditions + existingPath.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { paths, path in
                if !path.isEmpty && !paths.contains(path) {
                    paths.append(path)
                }
            }
            .joined(separator: ":")
        environment["PATH"] = mergedPath
        return environment
    }
}

private final class CodexOutputStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""
    private var pendingStdout = ""
    private var finished = false

    func appendStdout(_ text: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        stdout += text
        pendingStdout += text
        let parts = pendingStdout.components(separatedBy: .newlines)
        pendingStdout = parts.last ?? ""
        return parts.dropLast().filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func appendStderr(_ text: String) {
        lock.lock()
        stderr += text
        lock.unlock()
    }

    func takePendingRemainder() -> String {
        lock.lock()
        defer { lock.unlock() }
        let remainder = pendingStdout
        pendingStdout = ""
        return remainder
    }

    func snapshot() -> (stdout: String, stderr: String) {
        lock.lock()
        defer { lock.unlock() }
        return (stdout, stderr)
    }

    func claimFinish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}

enum CodexRunError: LocalizedError {
    case nonZeroExit(code: Int32, stderr: String)
    case decodeFailed(message: String, body: String)

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(code, stderr):
            return "codex exec exited \(code): \(stderr)"
        case let .decodeFailed(message, body):
            return "Could not decode Codex final response: \(message)\n\(body)"
        }
    }
}
