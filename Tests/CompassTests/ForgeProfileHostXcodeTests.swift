import Foundation
import Testing

@testable import Compass

struct ForgeProfileHostXcodeTests {
  @Test func testPrefersHostXcodeBridgeForSwiftPMRepo() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "ForgeProfileHostXcode-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// swift-tools-version: 5.9\n".write(
      to: root.appending(path: "Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    #expect(ForgeProfileService.prefersHostXcodeBridge(in: root))
  }

  @Test func testPrefersHostXcodeBridgeForXcodeprojRepo() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "ForgeProfileHostXcode-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: root.appending(path: "App.xcodeproj", directoryHint: .isDirectory),
      withIntermediateDirectories: true
    )
    #expect(ForgeProfileService.prefersHostXcodeBridge(in: root))
  }

  @Test func testDoesNotPreferHostXcodeBridgeForGoModule() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "ForgeProfileHostXcode-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "module example.com/app\n\ngo 1.22\n".write(
      to: root.appending(path: "go.mod"),
      atomically: true,
      encoding: .utf8
    )
    #expect(!ForgeProfileService.prefersHostXcodeBridge(in: root))
  }
}
