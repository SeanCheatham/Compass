import Testing

@testable import Compass

struct ClipboardHelpTextTests {
  @Test
  func copyHelpTextUsesPlainUserLanguage() {
    let forbiddenTerms = [
      "another model",
      "bounded",
      "handoff",
      "packet",
      "teammate",
      "Shared VM",
      "guest",
      "IPSW",
      "SSH",
      "sandbox",
    ]

    for text in ClipboardHelpText.allUserFacing {
      #expect(text.hasPrefix("Copy "))
      #expect(text.count <= 130)

      let normalized = text.lowercased()
      for term in forbiddenTerms {
        #expect(!normalized.contains(term.lowercased()))
      }
    }
  }

  @Test
  func privateWorkspaceCopyHelpNamesTheUserConcept() {
    #expect(ClipboardHelpText.privateWorkspaceReadiness.contains("private workspace"))
    #expect(ClipboardHelpText.runtimeDiagnostics.contains("workspace readiness"))
  }
}
