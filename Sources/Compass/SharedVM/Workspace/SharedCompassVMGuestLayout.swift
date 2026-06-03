import Foundation

/// Guest filesystem layout for the Shared VM route.
///
/// The current implementation still provisions a macOS guest, but generated
/// Rust workflows should depend on this layout contract rather than scattering
/// macOS home-directory assumptions through sync and verification code.
struct SharedCompassVMGuestLayout: Equatable, Sendable {
  var id: String
  var guestUserName: String
  var homeDirectory: String

  static let currentMacOS = SharedCompassVMGuestLayout(
    id: "macos-current",
    guestUserName: "compass",
    homeDirectory: "/Users/compass"
  )

  static let futureLinux = SharedCompassVMGuestLayout(
    id: "linux-future",
    guestUserName: "compass",
    homeDirectory: "/home/compass"
  )

  static let current = currentMacOS

  var reposRoot: String {
    "\(homeDirectory)/Compass/Repos"
  }

  func worktreePath(workspaceID: String, subdirectory: String) -> String {
    "\(reposRoot)/\(workspaceID)/\(subdirectory)"
  }
}
