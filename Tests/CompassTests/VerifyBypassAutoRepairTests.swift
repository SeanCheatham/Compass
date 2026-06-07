import Testing

@testable import Compass

struct VerifyBypassAutoRepairTests {
  @Test func repairsRustSortedDiffExpectedListBypass() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "All tests pass.",
      feedback:
        "Verify command is wrong: the expected= file list uses git diff --name-only output but is not sorted alphabetically.",
      bypassVerify: true
    )

    let repair = try #require(
      VerifyBypassAutoRepair.repair(
        plannedCommand:
          "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings",
        developSummary: summary,
        forgeProfile: .rustCargo
      )
    )

    try #require(repair.reason == .sortedDiffFileList)
    try #require(repair.command == "cargo run -p xtask -- verify")
  }

  @Test func doesNotRepairUnrelatedConcreteBypass() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Implementation completed.",
      feedback:
        "Verify command is wrong because DraftReadinessOldTests no longer exists; next Plan should replace it.",
      bypassVerify: true
    )

    let repair = VerifyBypassAutoRepair.repair(
      plannedCommand: "swift test --filter DraftReadinessOldTests",
      developSummary: summary,
      forgeProfile: .swiftSPM
    )

    try #require(repair == nil)
  }

  @Test func doesNotRepairWhenVerifyWasNotBypassed() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Implementation completed.",
      feedback: "No follow-up; verified cargo run -p xtask -- verify.",
      bypassVerify: false
    )

    let repair = VerifyBypassAutoRepair.repair(
      plannedCommand: "cargo run -p xtask -- verify",
      developSummary: summary,
      forgeProfile: .rustCargo
    )

    try #require(repair == nil)
  }
}
