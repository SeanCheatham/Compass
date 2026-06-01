import Testing

@testable import Compass

struct SandboxReadinessGuideTests {
  @Test
  func notProvisionedGuideExplainsPrivateWorkspaceSetup() {
    let guide = SandboxReadinessGuide(readiness: .notProvisioned)

    #expect(guide.title == "Private Workspace Not Installed")
    #expect(guide.actionLabel == "Provision Shared VM")
    #expect(guide.tone == .action)
    #expect(guide.steps.map(\.id) == ["download", "install", "guest", "tools"])
    #expect(guide.steps.allSatisfy { !$0.isComplete })
    #expect(guide.detail.contains("private macOS guest"))
    #expect(guide.allowsNarration)
  }

  @Test
  func progressGuideBucketsWorkWithoutNarrationSpam() {
    let guide = SandboxReadinessGuide(readiness: .provisioningDevTools(fractionCompleted: 0.43))

    #expect(guide.title == "Installing Developer Tools")
    #expect(guide.actionLabel == "43%")
    #expect(guide.tone == .progress)
    #expect(!guide.allowsNarration)
    #expect(guide.steps[0].isComplete)
    #expect(guide.steps[1].isComplete)
    #expect(guide.steps[2].isComplete)
    #expect(!guide.steps[3].isComplete)
    #expect(guide.steps[3].detail.contains("43%"))
  }

  @Test
  func readyGuideNamesSandboxRoute() {
    let guide = SandboxReadinessGuide(readiness: .ready(sshDestination: "compass@10.0.0.42"))

    #expect(guide.title == "Sandbox Ready")
    #expect(guide.actionLabel == "Ready")
    #expect(guide.tone == .ready)
    #expect(guide.steps.allSatisfy { $0.isComplete })
    #expect(guide.detail.contains("compass@10.0.0.42"))
  }

  @Test
  func errorGuideBoundsDetailsAndOffersRepair() {
    let guide = SandboxReadinessGuide(
      readiness: .error(detail: String(repeating: "install log line ", count: 40))
    )

    #expect(guide.title == "Sandbox Needs Repair")
    #expect(guide.tone == .blocked)
    #expect(guide.detail.count <= SandboxReadinessGuide.detailLimit)
    #expect(guide.steps.map(\.id) == ["repair"])
    #expect(guide.steps[0].detail.contains("local IPSW"))
  }

  @Test
  func sandboxClipboardPayloadPackagesErrorForRepair() {
    let readiness = SharedCompassVMReadiness.error(
      detail: "restore failed: unable to mount guest disk"
    )
    let guide = SandboxReadinessGuide(readiness: readiness)

    let payload = SandboxReadinessClipboardPayload(
      readiness: readiness,
      guide: guide
    )

    #expect(payload.text.contains("Compass Sandbox Handoff"))
    #expect(payload.text.contains("Do not invent logs"))
    #expect(payload.text.contains("Status: Sandbox Needs Repair (blocked)"))
    #expect(payload.text.contains("Action: Repair sandbox"))
    #expect(payload.text.contains("Readiness: error: restore failed"))
    #expect(payload.text.contains("[open] Recover install"))
    #expect(payload.text.contains("local IPSW"))
    #expect(payload.text.count <= SandboxReadinessClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
  }

  @Test
  func sandboxClipboardPayloadPreservesProgressState() {
    let readiness = SharedCompassVMReadiness.provisioningDevTools(fractionCompleted: 0.43)
    let guide = SandboxReadinessGuide(readiness: readiness)

    let payload = SandboxReadinessClipboardPayload(
      readiness: readiness,
      guide: guide
    )

    #expect(payload.text.contains("Status: Installing Developer Tools (progress)"))
    #expect(payload.text.contains("Action: 43%"))
    #expect(payload.text.contains("Readiness: installing developer tools: 43%"))
    #expect(payload.text.contains("If the packet is progress-only, wait"))
    #expect(payload.text.contains("[complete] Restore image"))
    #expect(payload.text.contains("[complete] macOS install"))
    #expect(payload.text.contains("[complete] Guest access"))
    #expect(payload.text.contains("[open] Developer tools"))
  }

  @Test
  func sandboxClipboardPayloadNamesReadyRoute() {
    let readiness = SharedCompassVMReadiness.ready(sshDestination: "compass@10.0.0.42")
    let guide = SandboxReadinessGuide(readiness: readiness)

    let payload = SandboxReadinessClipboardPayload(
      readiness: readiness,
      guide: guide
    )

    #expect(payload.text.contains("Status: Sandbox Ready (ready)"))
    #expect(payload.text.contains("Readiness: ready via compass@10.0.0.42"))
    #expect(payload.text.contains("[complete] Restore image"))
    #expect(payload.text.contains("[complete] Developer tools"))
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalSandboxPolish() async throws {
    let guide = SandboxReadinessGuide(readiness: .guestPrepping)

    try await withMockFoundationModels(
      response: "Compass is finishing guest access now; the sandbox will unlock when SSH responds."
    ) {
      let generatedNarration = await SandboxReadinessGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(
        narration.text
          == "Compass is finishing guest access now; the sandbox will unlock when SSH responds."
      )
    }
  }

  @Test
  func narratorSkipsProgressAndRejectsStructuredOutput() async {
    let progressGuide = SandboxReadinessGuide(
      readiness: .downloadingIPSW(fractionCompleted: 0.2)
    )

    await withMockFoundationModels(response: "Still downloading.") {
      let narration = await SandboxReadinessGuideNarrator.narrate(guide: progressGuide)
      #expect(narration == nil)
    }

    let guide = SandboxReadinessGuide(readiness: .notProvisioned)
    await withMockFoundationModels(response: #"{"text":"invented"}"#) {
      let narration = await SandboxReadinessGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await SandboxReadinessGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }
}
