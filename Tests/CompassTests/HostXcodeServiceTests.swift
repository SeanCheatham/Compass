import Foundation
import Testing

@testable import Compass

struct HostXcodeServiceTests {

  @Test func testInvocationInjectsCompassOwnedDerivedDataPath() throws {
    let workingDirectory = URL(fileURLWithPath: "/tmp/work")
    let derivedData = URL(fileURLWithPath: "/tmp/CompassDerivedData")

    let invocation = try HostXcodeService.makeXcodebuildInvocation(
      xcodebuildPath: "/usr/bin/xcodebuild",
      action: .build,
      arguments: ["-scheme", "App"],
      workingDirectory: workingDirectory,
      derivedDataPath: derivedData
    )

    #expect(invocation.executable == "/usr/bin/xcodebuild")
    #expect(invocation.workingDirectory == workingDirectory.standardizedFileURL)
    #expect(
      invocation.arguments == [
        "-scheme", "App", "-derivedDataPath", derivedData.path, "build",
      ]
    )
  }

  @Test func testInvocationDoesNotDuplicateExistingDerivedDataPath() throws {
    let workingDirectory = URL(fileURLWithPath: "/tmp/work")
    let derivedData = URL(fileURLWithPath: "/tmp/CompassDerivedData")

    let invocation = try HostXcodeService.makeXcodebuildInvocation(
      xcodebuildPath: "/usr/bin/xcodebuild",
      action: .test,
      arguments: ["-scheme", "App", "-derivedDataPath", "/tmp/custom"],
      workingDirectory: workingDirectory,
      derivedDataPath: derivedData
    )

    #expect(invocation.arguments == ["-scheme", "App", "-derivedDataPath", "/tmp/custom", "test"])
  }

  @Test func testInvocationRejectsActionsInsideArguments() throws {
    var message = ""
    do {
      _ = try HostXcodeService.makeXcodebuildInvocation(
        xcodebuildPath: "/usr/bin/xcodebuild",
        action: .build,
        arguments: ["-scheme", "App", "test"],
        workingDirectory: URL(fileURLWithPath: "/tmp/work"),
        derivedDataPath: URL(fileURLWithPath: "/tmp/dd")
      )
    } catch {
      message = error.localizedDescription
    }

    #expect(message.contains("flags only"))
  }

  @Test func testParseVerifyCommandAcceptsQuotedXcodebuildTest() throws {
    let parsed = try HostXcodeService.parseVerifyCommand(
      "xcodebuild -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17' test"
    )

    #expect(parsed.action == .test)
    #expect(
      parsed.arguments == [
        "-workspace", "App.xcworkspace",
        "-scheme", "App",
        "-destination", "platform=iOS Simulator,name=iPhone 17",
      ]
    )
  }

  @Test func testParseVerifyCommandRejectsNonXcodebuildCommands() throws {
    var message = ""
    do {
      _ = try HostXcodeService.parseVerifyCommand("xcrun simctl list")
    } catch {
      message = error.localizedDescription
    }

    #expect(message.contains("expected an `xcodebuild"))
  }

  @Test func testRunBuildUsesReadyHostXcodeAndConstructsArgv() async throws {
    let recorder = HostXcodeInvocationRecorder()
    let root = FileManager.default.temporaryDirectory
      .appending(path: "HostXcodeServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let repo = root.appending(path: "repo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let service = HostXcodeService(
      hostRepoURL: repo,
      mirrorRootURL: root.appending(path: "mirrors", directoryHint: .isDirectory),
      runner: { invocation, _, _, _, _ in
        await recorder.handle(invocation)
      }
    )

    let result = try await service.run(
      action: .build,
      arguments: ["-scheme", "App"],
      timeout: 10
    )
    let invocations = await recorder.invocations
    let final = try #require(invocations.last)
    let derivedData = HostXcodeService.derivedDataDirectory(
      forRepoURL: repo,
      rootURL: root.appending(path: "mirrors", directoryHint: .isDirectory)
    )

    #expect(result.exitCode == 0)
    #expect(final.executable == "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild")
    #expect(final.workingDirectory == repo.standardizedFileURL)
    #expect(final.arguments == ["-scheme", "App", "-derivedDataPath", derivedData.path, "build"])
  }

  @Test func testStatusExplainsCommandLineToolsSelection() async {
    let service = HostXcodeService(
      hostRepoURL: URL(fileURLWithPath: "/tmp/repo"),
      runner: { invocation, _, _, _, _ in
        if invocation.executable == "/usr/bin/xcode-select" {
          return ProcessResult(
            exitCode: 0,
            stdout: "/Library/Developer/CommandLineTools\n",
            stderr: ""
          )
        }
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
    )

    let status = await service.status()

    #expect(!status.isReady)
    #expect(status.unavailableReason?.contains("not full Xcode") == true)
  }

  @MainActor
  @Test func testVerifyRoutesThroughHostXcodeOnlyWhenEnabledAndRequired() async throws {
    let recorder = HostXcodeInvocationRecorder()
    let root = FileManager.default.temporaryDirectory
      .appending(path: "HostXcodeVerifyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let repo = root.appending(path: "repo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let project = CompassProject(repoURL: repo)
    let result = try await project.runVerifyCommand(
      command: "xcodebuild -scheme App build",
      hostWorkingDirectory: repo,
      timeoutSeconds: 10,
      launchPlan: .host(),
      requiresHostXcode: true,
      hostXcodeBuildTestEnabled: true,
      hostXcodeMirrorRoot: root.appending(path: "mirrors", directoryHint: .isDirectory),
      hostRunner: { invocation, _, _, _, _ in
        await recorder.handle(invocation)
      }
    )
    let hostXcodeInvocations = await recorder.invocations
    let final = try #require(hostXcodeInvocations.last)

    #expect(result.exitCode == 0)
    #expect(final.executable.contains("xcodebuild"))
    #expect(final.arguments.last == "build")

    let shellRecorder = HostXcodeInvocationRecorder()
    _ = try await project.runVerifyCommand(
      command: "xcodebuild -scheme App build",
      hostWorkingDirectory: repo,
      timeoutSeconds: 10,
      launchPlan: .host(),
      requiresHostXcode: true,
      hostXcodeBuildTestEnabled: false,
      hostRunner: { invocation, _, _, _, _ in
        await shellRecorder.handle(invocation)
      }
    )
    let shellInvocations = await shellRecorder.invocations
    let shell = try #require(shellInvocations.first)

    #expect(shell.executable == "/bin/zsh")
    #expect(shell.arguments == ["-lc", "xcodebuild -scheme App build"])
  }
}

private actor HostXcodeInvocationRecorder {
  private(set) var invocations: [AgentExecutionInvocation] = []

  func handle(_ invocation: AgentExecutionInvocation) -> ProcessResult {
    invocations.append(invocation)
    switch (invocation.executable, invocation.arguments) {
    case ("/usr/bin/xcode-select", ["-p"]):
      return ProcessResult(
        exitCode: 0,
        stdout: "/Applications/Xcode.app/Contents/Developer\n",
        stderr: ""
      )
    case ("/usr/bin/xcrun", ["--find", "xcodebuild"]):
      return ProcessResult(
        exitCode: 0,
        stdout: "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild\n",
        stderr: ""
      )
    case ("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", ["-version"]):
      return ProcessResult(exitCode: 0, stdout: "Xcode 17.0\n", stderr: "")
    case ("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", ["-checkFirstLaunchStatus"]):
      return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    default:
      return ProcessResult(exitCode: 0, stdout: "ok", stderr: "")
    }
  }
}
