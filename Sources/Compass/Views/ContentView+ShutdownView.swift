import AppKit

func copyTextToPasteboard(_ text: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(text, forType: .string)
}

func copyRuntimeDiagnosticsToPasteboard(_ text: String) {
  copyTextToPasteboard(text)
}
