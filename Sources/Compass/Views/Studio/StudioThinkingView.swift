import AppKit
import CompassCore
import SwiftUI

struct StudioThinkingView: View {
  @ObservedObject var state: StudioState

  private var scrollEpoch: String {
    guard let last = state.thinkingEntries.last else { return "empty" }
    return "\(state.thinkingEntries.count):\(last.id.uuidString):\(last.text.count)"
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "brain")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Text("Thinking")
          .font(.callout.weight(.semibold))
        Spacer(minLength: 0)
        Text("\(state.thinkingEntries.count)")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(state.thinkingEntries) { entry in
              StudioThinkingEntryView(entry: entry)
                .id(entry.id)
            }
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
          scrollToBottom(proxy: proxy)
        }
        .onChange(of: scrollEpoch) {
          scrollToBottom(proxy: proxy)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
  }

  private func scrollToBottom(proxy: ScrollViewProxy) {
    guard let last = state.thinkingEntries.last else { return }
    DispatchQueue.main.async {
      proxy.scrollTo(last.id, anchor: .bottom)
    }
  }
}

private struct StudioThinkingEntryView: View {
  let entry: StudioState.ThinkingEntry
  @State private var isHovered = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text("◆")
          .foregroundStyle(.secondary)
        Text("turn")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
        Spacer(minLength: 4)
        if isHovered {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
          } label: {
            Image(systemName: "doc.on.doc")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Copy thinking")
        }
      }
      Text(entry.text)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }
    .onHover { isHovered = $0 }
  }
}
