import AppKit
import CompassCore
import SwiftUI

struct StudioTerminalView: View {
  @ObservedObject var state: StudioState
  @Environment(\.colorScheme) private var colorScheme

  /// Bumps when the latest entry is added or its output is filled in.
  private var scrollEpoch: String {
    guard let last = state.terminalEntries.last else { return "empty" }
    let outputState =
      last.output.map { "done:\($0.count):\(last.isError == true)" } ?? "pending"
    return "\(state.terminalEntries.count):\(last.id.uuidString):\(outputState)"
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "terminal")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Text("Terminal")
          .font(.callout.weight(.semibold))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      Divider()
      // Keep ScrollView mounted even when empty so the first bash (often the
      // event that opens Studio) does not remount the reader mid-layout.
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            if state.terminalEntries.isEmpty {
              Text("bash commands the agent runs will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } else {
              ForEach(state.terminalEntries) { entry in
                StudioTerminalEntryView(entry: entry, colorScheme: colorScheme)
                  .id(entry.id)
              }
            }
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
          scrollToBottom(proxy: proxy, animated: false)
        }
        .onChange(of: scrollEpoch) {
          scrollToBottom(proxy: proxy, animated: false)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
  }

  private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
    guard let last = state.terminalEntries.last else { return }
    // Wait one turn so the entry row exists in the hierarchy (important when
    // Studio first opens on a bash-only session and this view mounts with
    // content already present).
    DispatchQueue.main.async {
      if animated {
        withAnimation(.easeOut(duration: 0.15)) {
          proxy.scrollTo(last.id, anchor: .bottom)
        }
      } else {
        proxy.scrollTo(last.id, anchor: .bottom)
      }
    }
  }
}

private struct StudioTerminalEntryView: View {
  let entry: StudioState.TerminalEntry
  let colorScheme: ColorScheme
  @State private var isHovered = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text("$")
          .foregroundStyle(.tertiary)
        Text(entry.command)
          .fontWeight(.medium)
          .lineLimit(2)
          .truncationMode(.tail)
          .foregroundStyle(.primary)
        if let cwd = entry.cwd, !cwd.isEmpty, cwd != "/" {
          Text("(\(cwd))")
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        if isHovered, let output = entry.output, !output.isEmpty {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
              StudioANSIParser.strip(output),
              forType: .string
            )
          } label: {
            Image(systemName: "doc.on.doc")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Copy output")
        }
        statusBadge
      }
      .font(.system(.callout, design: .monospaced))
      if let output = entry.output, !output.isEmpty {
        Text(
          StudioANSIParser.attributedString(
            output,
            options: .init(defaultForeground: defaultOutputColor)
          )
        )
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
      }
    }
    .onHover { isHovered = $0 }
  }

  private var defaultOutputColor: NSColor {
    if entry.isError == true {
      return .systemRed
    }
    // Resolve against the current scheme so AttributedString doesn't keep a
    // stale dark-panel gray after appearance changes.
    return colorScheme == .dark
      ? NSColor(calibratedWhite: 0.78, alpha: 1)
      : NSColor(calibratedWhite: 0.28, alpha: 1)
  }

  @ViewBuilder
  private var statusBadge: some View {
    if entry.output == nil {
      ProgressView()
        .controlSize(.mini)
    } else if entry.isError == true {
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
        .font(.system(size: 11))
    } else {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.system(size: 11))
    }
  }
}
