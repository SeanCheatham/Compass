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
        onEvent: @escaping (String) -> Void
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
        onEvent: @escaping (String) -> Void
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
                onEvent(chunk.trimmingCharacters(in: .newlines))
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

    private static func renderJSONLine(_ line: String) -> String {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return line
        }

        let type = object["type"] as? String ?? "event"
        if let item = object["item"] as? [String: Any],
           let itemType = item["type"] as? String {
            switch itemType {
            case "command_execution":
                let command = item["command"] as? String ?? "(command)"
                return "\(type): \(command)"
            case "agent_message":
                let text = item["text"] as? String ?? ""
                return summarizeAgentMessage(text, eventType: type)
            case "file_change":
                return "\(type): file changes"
            default:
                return "\(type): \(itemType)"
            }
        }

        if let message = object["message"] as? String {
            return "\(type): \(message)"
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return "\(type): \(message)"
        }
        return type
    }

    private static func summarizeAgentMessage(_ text: String, eventType: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\(eventType): agent_message" }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let completed = object["completed"] as? [Any],
               object.keys.contains("immediate"),
               object.keys.contains("midTerm"),
               object.keys.contains("longTerm") {
                let immediate = object["immediate"] as? [String: Any]
                let plan = firstLine(immediate?["plan"] as? String) ?? "none"
                let verify = firstLine(immediate?["verify"] as? String) ?? "none"
                return "Codex candidate PlanState (streamed; not accepted yet): completed=\(completed.count), immediate=\(plan), verify=\(verify)"
            }

            if let status = object["status"] as? String,
               object.keys.contains("summary"),
               object.keys.contains("feedback") {
                let summary = firstLine(object["summary"] as? String) ?? ""
                return "Codex candidate DevelopSummary (streamed; not accepted yet): status=\(status), summary=\(summary)"
            }
        }

        return "Codex: \(trimmed)"
    }

    private static func firstLine(_ text: String?) -> String? {
        text?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
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
