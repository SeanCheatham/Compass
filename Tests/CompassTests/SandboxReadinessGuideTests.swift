import Testing

@testable import Compass

struct SandboxReadinessGuideTests {
  @Test
  func notProvisionedGuideExplainsPrivateWorkspaceSetup() {
    let guide = SandboxReadinessGuide(readiness: .notProvisioned)

    #expect(guide.title == "Private Workspace Not Installed")
    #expect(guide.actionLabel == "Set Up Workspace")
    #expect(guide.tone == .action)
    #expect(guide.steps.map(\.id) == ["download", "install", "guest", "tools"])
    #expect(guide.steps.allSatisfy { !$0.isComplete })
    #expect(guide.detail.contains("private workspace"))
    #expect(!guide.detail.contains("Shared VM"))
    #expect(!guide.detail.contains("guest"))
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
    #expect(guide.steps[2].title == "Workspace access")
    #expect(guide.steps[3].detail.contains("43%"))
  }

  @Test
  func readyGuideNamesSandboxRoute() {
    let guide = SandboxReadinessGuide(readiness: .ready(sshDestination: "compass@10.0.0.42"))

    #expect(guide.title == "Private Workspace Ready")
    #expect(guide.actionLabel == "Ready")
    #expect(guide.tone == .ready)
    #expect(guide.steps.allSatisfy { $0.isComplete })
    #expect(!guide.detail.contains("compass@10.0.0.42"))
    #expect(!guide.detail.contains("Shared VM"))
    #expect(!guide.detail.contains("SSH"))
    #expect(!guide.detail.contains("guest"))
  }

  @Test
  func errorGuideBoundsDetailsAndOffersRepair() {
    let guide = SandboxReadinessGuide(
      readiness: .error(detail: String(repeating: "install log line ", count: 40))
    )

    #expect(guide.title == "Private Workspace Needs Repair")
    #expect(guide.tone == .blocked)
    #expect(guide.detail.count <= SandboxReadinessGuide.detailLimit)
    #expect(guide.steps.map(\.id) == ["repair"])
    #expect(guide.steps[0].detail.contains("downloaded macOS restore image"))
    #expect(!guide.steps[0].detail.contains("IPSW"))
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

    #expect(payload.text.contains("Compass Private Workspace Handoff"))
    #expect(payload.text.contains("Do not invent logs"))
    #expect(payload.text.contains("Status: Private Workspace Needs Repair (blocked)"))
    #expect(payload.text.contains("Action: Repair Workspace"))
    #expect(payload.text.contains("Readiness: error: restore failed"))
    #expect(payload.text.contains("workspace disk"))
    #expect(payload.text.contains("[open] Recover install"))
    #expect(payload.text.contains("downloaded macOS restore image"))
    #expect(!payload.text.contains("Shared VM"))
    #expect(!payload.text.contains("SSH"))
    #expect(!payload.text.contains("IPSW"))
    #expect(!payload.text.contains("guest"))
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
    #expect(payload.text.contains("[complete] Workspace access"))
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

    #expect(payload.text.contains("Status: Private Workspace Ready (ready)"))
    #expect(payload.text.contains("Readiness: ready"))
    #expect(!payload.text.contains("compass@10.0.0.42"))
    #expect(payload.text.contains("[complete] Restore image"))
    #expect(payload.text.contains("[complete] Developer tools"))
  }

  @Test
  func sandboxReadinessDisplayHelpersUsePrivateWorkspaceCopy() {
    let unavailable = SharedCompassVMReadiness.unavailable(
      reason: "Shared VM unavailable: 2-guest cap"
    )
    let error = SharedCompassVMReadiness.error(
      detail: "SSH failed while mounting the guest disk"
    )
    let ready = SharedCompassVMReadiness.ready(sshDestination: "compass@10.0.0.42")
    let visibleTexts = [
      SharedCompassVMReadiness.notProvisioned.statusSummary,
      SharedCompassVMReadiness.notProvisioned.placeholderTitle,
      SharedCompassVMReadiness.notProvisioned.placeholderDetail,
      SharedCompassVMReadiness.downloadingIPSW(fractionCompleted: 0.4).statusSummary,
      SharedCompassVMReadiness.guestPrepping.statusSummary,
      SharedCompassVMReadiness.guestPrepping.placeholderTitle,
      SharedCompassVMReadiness.guestPrepping.placeholderDetail,
      unavailable.statusSummary,
      unavailable.placeholderTitle,
      unavailable.placeholderDetail,
      error.statusSummary,
      error.placeholderTitle,
      error.placeholderDetail,
      ready.placeholderTitle,
      ready.placeholderDetail,
    ]

    for text in visibleTexts {
      #expect(!text.contains("Shared VM"))
      #expect(!text.contains("SSH"))
      #expect(!text.contains("IPSW"))
      #expect(!text.contains("guest"))
      #expect(!text.contains("compass@10.0.0.42"))
    }
    #expect(unavailable.statusSummary.contains("workspace capacity limit"))
    #expect(error.placeholderDetail.contains("secure connection"))
    #expect(ready.placeholderTitle == "Private workspace is ready")
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalSandboxPolish() async throws {
    let guide = SandboxReadinessGuide(readiness: .guestPrepping)

    try await withMockFoundationModels(
      response: "Compass is finishing workspace setup now; Develop will unlock when commands can run."
    ) {
      let generatedNarration = await SandboxReadinessGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(
        narration.text
          == "Compass is finishing workspace setup now; Develop will unlock when commands can run."
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

    await withMockFoundationModels(response: "Compass is waiting for SSH in the guest.") {
      let narration = await SandboxReadinessGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }
}
