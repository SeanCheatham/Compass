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

  @Test func testDoesNotPreferHostXcodeBridgeForCargoRepo() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "ForgeProfileHostXcode-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "[package]\nname = \"app\"\nversion = \"0.1.0\"\n".write(
      to: root.appending(path: "Cargo.toml"),
      atomically: true,
      encoding: .utf8
    )
    #expect(!ForgeProfileService.prefersHostXcodeBridge(in: root))
  }
}
