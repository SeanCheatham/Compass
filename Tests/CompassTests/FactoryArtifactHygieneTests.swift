import Foundation
import Testing

@testable import Compass

struct FactoryArtifactHygieneTests {
  @Test func flagsGeneratedDirectoriesAndObjectFiles() throws {
    let output = """
      A\ttarget/debug/app
      A\tFoundationProvider-1.o
      A\t__.SYMDEF SORTED
      M\tSources/App.swift
      D\ttarget/old.o
      """

    let issues = FactoryArtifactHygiene.issues(fromGitNameStatus: output)

    try #require(issues.map(\.path) == [
      "target/debug/app",
      "FoundationProvider-1.o",
      "__.SYMDEF SORTED",
    ])
    try #require(issues[0].reason.contains("generated directory"))
    try #require(issues[1].reason.contains(".o"))
  }

  @Test func parsesRenamedPathsUsingDestinationPath() throws {
    let output = "R100\tSources/Old.swift\tbuild/generated.o\n"

    let issues = FactoryArtifactHygiene.issues(fromGitNameStatus: output)

    try #require(issues.count == 1)
    try #require(issues.first?.path == "build/generated.o")
  }

  @Test func formatsActionablePostCheckMessage() throws {
    let issues = [
      FactoryArtifactHygieneIssue(path: "target/debug/app", reason: "inside generated directory `target/`")
    ]

    let message = try #require(FactoryArtifactHygiene.formattedIssue(from: issues))

    try #require(message.contains("[artifact-hygiene]"))
    try #require(message.contains("target/debug/app"))
    try #require(message.contains(".gitignore"))
  }
}
