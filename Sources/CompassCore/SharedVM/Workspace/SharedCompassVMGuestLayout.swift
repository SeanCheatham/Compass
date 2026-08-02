import Foundation

/// Guest filesystem layout for the Shared VM route.
///
/// The current implementation still provisions a macOS guest, but generated
/// TypeScript workflows should depend on this layout contract rather than scattering
/// macOS home-directory assumptions through sync and verification code.
public struct SharedCompassVMGuestLayout: Equatable, Sendable {
  public var id: String
  public var guestUserName: String
  public var homeDirectory: String

  public static let currentMacOS = SharedCompassVMGuestLayout(
    id: "macos-current",
    guestUserName: "compass",
    homeDirectory: "/Users/compass"
  )

  public static let futureLinux = SharedCompassVMGuestLayout(
    id: "linux-future",
    guestUserName: "compass",
    homeDirectory: "/home/compass"
  )

  public static let current = currentMacOS

  public var reposRoot: String {
    "\(homeDirectory)/Compass/Repos"
  }

  public func worktreePath(workspaceID: String, subdirectory: String) -> String {
    "\(reposRoot)/\(workspaceID)/\(subdirectory)"
  }
}
