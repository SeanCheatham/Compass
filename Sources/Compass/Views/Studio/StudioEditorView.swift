import CompassCore
import SwiftUI

struct StudioEditorView: View {
  @ObservedObject var state: StudioState

  private static let highlightFadeSeconds: TimeInterval = 3

  var body: some View {
    if let path = state.openFile, let buffer = state.buffers[path] {
      VStack(spacing: 0) {
        breadcrumb(path: path)
        Divider()
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
          let highlightOpacity = fadeOpacity(
            since: buffer.lastChangeAt,
            now: context.date
          )
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(buffer.lines.enumerated()), id: \.offset) { index, line in
                  let lineNumber = index + 1
                  HStack(spacing: 0) {
                    Text("\(lineNumber)")
                      .font(.system(.caption, design: .monospaced))
                      .foregroundStyle(.tertiary)
                      .frame(width: 44, alignment: .trailing)
                      .padding(.trailing, 10)
                    Text(line.isEmpty ? " " : line)
                      .font(.system(.callout, design: .monospaced))
                      .textSelection(.enabled)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .padding(.vertical, 1)
                  .background(
                    buffer.highlightedLines.contains(lineNumber)
                      ? Color.green.opacity(highlightOpacity)
                      : .clear
                  )
                  .id(lineNumber)
                }
              }
              .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: buffer.scrollToLine) {
              scrollToRevealedLine(proxy: proxy, buffer: buffer)
            }
            .onAppear {
              scrollToRevealedLine(proxy: proxy, buffer: buffer)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      VStack(spacing: 8) {
        Image(systemName: "doc.text.magnifyingglass")
          .font(.system(size: 26, weight: .light))
          .foregroundStyle(.tertiary)
        Text("No file open")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func breadcrumb(path: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "doc.plaintext")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Text(path.split(separator: "/").map(String.init).joined(separator: " › "))
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 0)
      Image(systemName: "lock.fill")
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .help("Read-only — the Studio editor mirrors what the agent does.")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
  }

  private func fadeOpacity(since changeAt: Date, now: Date) -> Double {
    let age = now.timeIntervalSince(changeAt)
    guard age < Self.highlightFadeSeconds else { return 0 }
    return 0.25 * (1 - age / Self.highlightFadeSeconds)
  }

  private func scrollToRevealedLine(
    proxy: ScrollViewProxy,
    buffer: StudioState.FileBuffer
  ) {
    guard let line = buffer.scrollToLine, line >= 1 else { return }
    DispatchQueue.main.async {
      withAnimation(.easeOut(duration: 0.25)) {
        proxy.scrollTo(line, anchor: .center)
      }
    }
  }
}
