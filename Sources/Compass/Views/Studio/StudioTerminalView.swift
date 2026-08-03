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
            LazyVStack(alignment: .leading, spacing: 10) {
              ForEach(state.terminalEntries) { entry in
                StudioTerminalEntryView(entry: entry)
                  .id(entry.id)
              }
            }
            .padding(10)
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
    .background(Color(nsColor: .textBackgroundColor))
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

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text("$")
          .foregroundStyle(.tertiary)
        Text(entry.command)
          .fontWeight(.medium)
          .lineLimit(2)
          .truncationMode(.tail)
        if let cwd = entry.cwd, !cwd.isEmpty, cwd != "/" {
          Text("(\(cwd))")
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        statusBadge
      }
      .font(.system(.callout, design: .monospaced))
      if let output = entry.output, !output.isEmpty {
        Text(output)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(entry.isError == true ? Color.red.opacity(0.85) : Color.secondary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 12)
      }
    }
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
