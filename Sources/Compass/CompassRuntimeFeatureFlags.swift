import Foundation

struct CompassRuntimeFeatureFlags: Equatable, Sendable {
  var rustDaemonEnabled: Bool
  var rustTournamentShadow: Bool
  var rustTournamentDriver: Bool
  var rustAgentExecutor: Bool
  var rustGuestAgent: Bool
  var linuxGuest: Bool

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    rustDaemonEnabled = environment["COMPASS_RUST_DAEMON_DISABLED"] != "1"
    rustTournamentShadow = environment["COMPASS_RUST_TOURNAMENT_SHADOW"] == "1"
    rustTournamentDriver = environment["COMPASS_RUST_TOURNAMENT_DRIVER"] == "1"
    rustAgentExecutor = environment["COMPASS_RUST_AGENT_EXECUTOR"] == "1"
    rustGuestAgent = environment["COMPASS_RUST_GUEST_AGENT"] == "1"
    linuxGuest = environment["COMPASS_LINUX_GUEST"] == "1"
  }

  var copyText: String {
    [
      "rustDaemonEnabled=\(rustDaemonEnabled)",
      "rustTournamentShadow=\(rustTournamentShadow)",
      "rustTournamentDriver=\(rustTournamentDriver)",
      "rustAgentExecutor=\(rustAgentExecutor)",
      "rustGuestAgent=\(rustGuestAgent)",
      "linuxGuest=\(linuxGuest)",
    ].joined(separator: "\n")
  }
}
