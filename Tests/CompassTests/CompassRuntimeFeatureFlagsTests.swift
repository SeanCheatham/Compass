import Testing

@testable import Compass

struct CompassRuntimeFeatureFlagsTests {
  @Test func flagsDefaultToDaemonOnly() {
    let flags = CompassRuntimeFeatureFlags(environment: [:])

    #expect(flags.rustDaemonEnabled)
    #expect(!flags.rustTournamentShadow)
    #expect(!flags.rustTournamentDriver)
    #expect(!flags.rustAgentExecutor)
    #expect(!flags.rustGuestAgent)
    #expect(!flags.linuxGuest)
    #expect(!flags.tournamentSchedulerPreview)
    #expect(!flags.tournamentParallelEvidence)
    #expect(!flags.tournamentParallelDevelop)
  }

  @Test func flagsReadEnvironmentOverrides() {
    let flags = CompassRuntimeFeatureFlags(environment: [
      "COMPASS_RUST_DAEMON_DISABLED": "1",
      "COMPASS_RUST_TOURNAMENT_SHADOW": "1",
      "COMPASS_RUST_TOURNAMENT_DRIVER": "1",
      "COMPASS_RUST_AGENT_EXECUTOR": "1",
      "COMPASS_RUST_GUEST_AGENT": "1",
      "COMPASS_LINUX_GUEST": "1",
      "COMPASS_TOURNAMENT_SCHEDULER_PREVIEW": "1",
      "COMPASS_TOURNAMENT_PARALLEL_EVIDENCE": "1",
      "COMPASS_TOURNAMENT_PARALLEL_DEVELOP": "1",
    ])

    #expect(!flags.rustDaemonEnabled)
    #expect(flags.rustTournamentShadow)
    #expect(flags.rustTournamentDriver)
    #expect(flags.rustAgentExecutor)
    #expect(flags.rustGuestAgent)
    #expect(flags.linuxGuest)
    #expect(flags.tournamentSchedulerPreview)
    #expect(flags.tournamentParallelEvidence)
    #expect(flags.tournamentParallelDevelop)
    #expect(flags.copyText.contains("tournamentSchedulerPreview=true"))
  }
}
