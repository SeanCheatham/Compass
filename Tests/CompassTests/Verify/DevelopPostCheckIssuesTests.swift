import Foundation
import Testing

@testable import CompassCore

@Suite("DevelopPostCheckIssues")
struct DevelopPostCheckIssuesTests {
  private let develop = DevelopSummary(
    status: .succeeded,
    summary: "Added tombstone deletes",
    feedback: "Verified with cargo test",
    bypassVerify: false,
    lessonEdits: []
  )

  @Test
  func dirtyTrackedFilesAreExpectedPendingHarnessCommit() {
    let assessment = DevelopPostCheckIssues.hostWorkingTreeIssues(
      porcelain: """
        M crates/core/src/model.rs
        M crates/core/src/store.rs
        """,
      changedPaths: [
        "crates/core/src/model.rs",
        "crates/core/src/store.rs",
      ],
      develop: develop
    )

    #expect(assessment.issues.isEmpty)
    #expect(assessment.dirtyPendingHarnessCommit)
  }

  @Test
  func cleanTreeWithChangesIsOk() {
    let assessment = DevelopPostCheckIssues.hostWorkingTreeIssues(
      porcelain: "",
      changedPaths: ["crates/core/src/model.rs"],
      develop: develop
    )

    #expect(assessment.issues.isEmpty)
    #expect(!assessment.dirtyPendingHarnessCommit)
  }

  @Test
  func successWithoutAnyChangesFails() {
    let assessment = DevelopPostCheckIssues.hostWorkingTreeIssues(
      porcelain: "",
      changedPaths: [],
      develop: develop
    )

    #expect(assessment.issues.count == 1)
    #expect(assessment.issues[0].contains("did not detect any Git-visible file changes"))
    #expect(!assessment.dirtyPendingHarnessCommit)
  }
}
