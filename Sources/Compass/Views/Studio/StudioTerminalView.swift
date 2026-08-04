import AppKit
import CompassCore
import SwiftUI

struct StudioTerminalView: View {
  @ObservedObject var state: StudioState

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
      if state.terminalEntries.isEmpty {
        Text("bash commands the agent runs will appear here")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
              ForEach(state.terminalEntries) { entry in
                StudioTerminalEntryView(entry: entry)
                  .id(entry.id)
              }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
          }
          .onChange(of: state.terminalEntries.count) {
            scrollToBottom(proxy: proxy)
          }
          .onChange(of: state.terminalEntries.last?.output != nil) {
            scrollToBottom(proxy: proxy)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.black.opacity(0.88))
    .foregroundStyle(Color.white.opacity(0.92))
  }

  private func scrollToBottom(proxy: ScrollViewProxy) {
    guard let last = state.terminalEntries.last else { return }
    DispatchQueue.main.async {
      withAnimation(.easeOut(duration: 0.15)) {
        proxy.scrollTo(last.id, anchor: .bottom)
      }
    }
  }
}

private struct StudioTerminalEntryView: View {
  let entry: StudioState.TerminalEntry
  @State private var isHovered = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text("$")
          .foregroundStyle(Color.white.opacity(0.35))
        Text(entry.command)
          .fontWeight(.medium)
          .lineLimit(2)
          .truncationMode(.tail)
          .foregroundStyle(Color.white.opacity(0.9))
        if let cwd = entry.cwd, !cwd.isEmpty, cwd != "/" {
          Text("(\(cwd))")
            .foregroundStyle(Color.white.opacity(0.35))
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
              .foregroundStyle(Color.white.opacity(0.55))
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
            options: .init(
              defaultForeground: entry.isError == true
                ? NSColor(calibratedRed: 1, green: 0.45, blue: 0.45, alpha: 1)
                : NSColor(calibratedWhite: 0.75, alpha: 1)
            )
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

  @ViewBuilder
  private var statusBadge: some View {
    if entry.output == nil {
      ProgressView()
        .controlSize(.mini)
        .colorInvert()
    } else if entry.isError == true {
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
        .font(.system(size: 11))
    } else {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(Color.green.opacity(0.85))
        .font(.system(size: 11))
    }
  }
}
