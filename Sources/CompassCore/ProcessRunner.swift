import Foundation

public struct ProcessResult: Sendable, Equatable {
  public var exitCode: Int32
  public var stdout: String
  public var stderr: String
}

private final class ProcessOutputStore: @unchecked Sendable {
  private let lock = NSLock()
  private var stdout = ""
  private var stderr = ""
  private var finished = false

  public func appendStdout(_ text: String) {
    lock.lock()
    stdout += text
    lock.unlock()
  }

  public func appendStderr(_ text: String) {
    lock.lock()
    stderr += text
    lock.unlock()
  }

  public func snapshot() -> (stdout: String, stderr: String) {
    lock.lock()
    defer { lock.unlock() }
    return (stdout, stderr)
  }

  public func claimFinish() -> Bool {
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

  public func set(_ workItem: DispatchWorkItem) {
    lock.lock()
    self.workItem = workItem
    lock.unlock()
  }

  public func cancel() {
    lock.lock()
    workItem?.cancel()
    workItem = nil
    lock.unlock()
  }
}

private final class ProcessBox: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?

  func set(_ process: Process) {
    lock.lock()
    self.process = process
    lock.unlock()
  }

  func terminate() {
    lock.lock()
    let process = self.process
    lock.unlock()
    if let process, process.isRunning {
      process.terminate()
    }
  }
}

public enum ProcessRunner {
  private static let timeoutQueue = DispatchQueue(
    label: "Compass.ProcessRunner.timeout",
    qos: .userInitiated
  )
  private static let outputQueue = DispatchQueue(
    label: "Compass.ProcessRunner.output",
    qos: .userInitiated,
    attributes: .concurrent
  )

  public typealias InvocationRunner = (
    _ invocation: AgentExecutionInvocation,
    _ input: String?,
    _ timeout: TimeInterval?,
    _ onStdout: ((String) -> Void)?,
    _ onStderr: ((String) -> Void)?
  ) async throws -> ProcessResult

  public static func run(
    executable: String,
    arguments: [String],
    workingDirectory: URL? = nil,
    input: String? = nil,
    timeout: TimeInterval? = nil,
    onStdout: ((String) -> Void)? = nil,
    onStderr: ((String) -> Void)? = nil
  ) async throws -> ProcessResult {
    try Task.checkCancellation()
    let processBox = ProcessBox()
    return try await withTaskCancellationHandler {
      try await runUninterruptible(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        input: input,
        timeout: timeout,
        onStdout: onStdout,
        onStderr: onStderr,
        processBox: processBox
      )
    } onCancel: {
      processBox.terminate()
    }
  }

  private static func runUninterruptible(
    executable: String,
    arguments: [String],
    workingDirectory: URL?,
    input: String?,
    timeout: TimeInterval?,
    onStdout: ((String) -> Void)?,
    onStderr: ((String) -> Void)?,
    processBox: ProcessBox
  ) async throws -> ProcessResult {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.currentDirectoryURL = workingDirectory
      processBox.set(process)

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      let stdinPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe
      let stdinNull = input == nil ? FileHandle(forReadingAtPath: "/dev/null") : nil
      if input != nil {
        process.standardInput = stdinPipe
      } else if let stdinNull {
        process.standardInput = stdinNull
      }

      let outputStore = ProcessOutputStore()
      let timeoutStore = TimeoutStore()
      let outputGroup = DispatchGroup()
      outputGroup.enter()
      outputGroup.enter()

      let finish: @Sendable (Result<ProcessResult, Error>) -> Void = { result in
        guard outputStore.claimFinish() else { return }

        try? stdinNull?.close()
        timeoutStore.cancel()
        continuation.resume(with: result)
      }

      process.terminationHandler = { process in
        outputGroup.notify(queue: timeoutQueue) {
          let snapshot = outputStore.snapshot()
          finish(
            .success(
              ProcessResult(
                exitCode: process.terminationStatus,
                stdout: snapshot.stdout,
                stderr: snapshot.stderr
              )))
        }
      }

      do {
        try process.run()
      } catch {
        outputGroup.leave()
        outputGroup.leave()
        finish(.failure(error))
        return
      }
      if Task.isCancelled {
        process.terminate()
      }
      try? stdoutPipe.fileHandleForWriting.close()
      try? stderrPipe.fileHandleForWriting.close()

      outputQueue.async {
        defer { outputGroup.leave() }
        drainOutput(
          from: stdoutPipe.fileHandleForReading,
          append: outputStore.appendStdout,
          callback: onStdout
        )
      }
      outputQueue.async {
        defer { outputGroup.leave() }
        drainOutput(
          from: stderrPipe.fileHandleForReading,
          append: outputStore.appendStderr,
          callback: onStderr
        )
      }

      if let input {
        let data = Data(input.utf8)
        stdinPipe.fileHandleForWriting.write(data)
        do {
          try stdinPipe.fileHandleForWriting.close()
        } catch {
          finish(.failure(error))
          return
        }
      }

      if let timeout {
        let work = DispatchWorkItem {
          if process.isRunning {
            process.terminate()
          }
        }
        timeoutStore.set(work)
        timeoutQueue.asyncAfter(deadline: .now() + timeout, execute: work)
      }
    }
  }

  private static func drainOutput(
    from handle: FileHandle,
    append: @escaping (String) -> Void,
    callback: ((String) -> Void)?
  ) {
    while true {
      do {
        guard let data = try handle.read(upToCount: 8_192), !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        append(chunk)
        callback?(chunk)
      } catch {
        return
      }
    }
  }

  public static func run(
    invocation: AgentExecutionInvocation,
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

  public static func runEnv(
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

  public static func runShell(
    _ command: String,
    workingDirectory: URL,
    timeout: TimeInterval? = nil,
    launchPlan: AgentExecutionLaunchPlan? = nil,
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
    _ invocation: AgentExecutionInvocation,
    timeout: TimeInterval?,
    runner: InvocationRunner?
  ) async throws -> ProcessResult {
    if let runner {
      return try await runner(invocation, nil, timeout, nil, nil)
    }

    return try await run(invocation: invocation, timeout: timeout)
  }
}
