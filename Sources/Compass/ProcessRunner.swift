import Foundation

struct ProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private final class ProcessOutputStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""
    private var finished = false

    func appendStdout(_ text: String) {
        lock.lock()
        stdout += text
        lock.unlock()
    }

    func appendStderr(_ text: String) {
        lock.lock()
        stderr += text
        lock.unlock()
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

private final class TimeoutStore: @unchecked Sendable {
    private let lock = NSLock()
    private var workItem: DispatchWorkItem?

    func set(_ workItem: DispatchWorkItem) {
        lock.lock()
        self.workItem = workItem
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        workItem?.cancel()
        workItem = nil
        lock.unlock()
    }
}

enum ProcessRunner {
    typealias InvocationRunner = (
        _ invocation: CodexExecutionInvocation,
        _ input: String?,
        _ timeout: TimeInterval?,
        _ onStdout: ((String) -> Void)?,
        _ onStderr: ((String) -> Void)?
    ) async throws -> ProcessResult

    static func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        input: String? = nil,
        timeout: TimeInterval? = nil,
        onStdout: ((String) -> Void)? = nil,
        onStderr: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if input != nil {
                process.standardInput = stdinPipe
            }

            let outputStore = ProcessOutputStore()
            let timeoutStore = TimeoutStore()

            let finish: @Sendable (Result<ProcessResult, Error>) -> Void = { result in
                guard outputStore.claimFinish() else { return }

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                timeoutStore.cancel()
                continuation.resume(with: result)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                outputStore.appendStdout(chunk)
                onStdout?(chunk)
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                outputStore.appendStderr(chunk)
                onStderr?(chunk)
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
                if let input {
                    let data = Data(input.utf8)
                    stdinPipe.fileHandleForWriting.write(data)
                    try stdinPipe.fileHandleForWriting.close()
                }
            } catch {
                finish(.failure(error))
                return
            }

            if let timeout {
                let work = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                timeoutStore.set(work)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
            }
        }
    }

    static func run(
        invocation: CodexExecutionInvocation,
        input: String? = nil,
        timeout: TimeInterval? = nil,
        onStdout: ((String) -> Void)? = nil,
        onStderr: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        try await run(
            executable: invocation.executable,
            arguments: invocation.arguments,
            workingDirectory: invocation.workingDirectory,
            input: input,
            timeout: timeout,
            onStdout: onStdout,
            onStderr: onStderr
        )
    }

    static func runEnv(
        _ command: String,
        _ arguments: [String],
        workingDirectory: URL? = nil,
        input: String? = nil,
        timeout: TimeInterval? = nil,
        onStdout: ((String) -> Void)? = nil,
        onStderr: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        try await run(
            executable: "/usr/bin/env",
            arguments: [command] + arguments,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            onStdout: onStdout,
            onStderr: onStderr
        )
    }

    static func runShell(
        _ command: String,
        workingDirectory: URL,
        timeout: TimeInterval? = nil,
        launchPlan: CodexExecutionLaunchPlan? = nil,
        runner: InvocationRunner? = nil
    ) async throws -> ProcessResult {
        let effectiveLaunchPlan = launchPlan ?? .host()
        let invocation = effectiveLaunchPlan.shellInvocation(
            command: command,
            hostWorkingDirectory: workingDirectory
        )
        return try await runInvocation(
            invocation,
            timeout: timeout,
            runner: runner
        )
    }

    private static func runInvocation(
        _ invocation: CodexExecutionInvocation,
        timeout: TimeInterval?,
        runner: InvocationRunner?
    ) async throws -> ProcessResult {
        if let runner {
            return try await runner(invocation, nil, timeout, nil, nil)
        }

        return try await run(invocation: invocation, timeout: timeout)
    }
}
