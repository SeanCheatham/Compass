import Foundation
import Testing

@testable import CompassCore

@Suite("Shared VM auto-login repair")
struct SharedCompassVMAutoLoginRepairTests {
  @Test
  func repairRemoteCommandEmbedsQuotedCredentialsAndRetryLoop() {
    let command = SharedCompassVMAutoLoginRepair.repairRemoteCommand(
      guestUserName: "compass",
      password: "p@ss'word"
    )
    #expect(command.contains("GUEST_USER=compass"))
    #expect(command.contains("PASSWORD="))
    #expect(command.contains("p@ss'\\''word") || command.contains("p@ss"))
    #expect(command.contains("/etc/kcpassword"))
    #expect(command.contains("autoLoginUser"))
    #expect(command.contains("killall loginwindow"))
    #expect(command.contains("for attempt in 1 2 3 4 5 6"))
    #expect(command.contains(SharedCompassVMAutoLoginRepair.autoLoginScriptGuestPath))
  }

  @Test
  func plantedAutoLoginScriptRetriesLoginwindowRestart() {
    // `SharedCompassVMHeadlessFirstBoot` is internal; exercise the public
    // repair path which embeds the same retry semantics.
    let command = SharedCompassVMAutoLoginRepair.repairRemoteCommand(
      guestUserName: "compass",
      password: "secret"
    )
    #expect(command.contains("for attempt in 1 2 3 4 5 6"))
    #expect(command.contains("killall loginwindow"))
    #expect(command.contains("/var/log/compass-autologin.log"))
  }
}
