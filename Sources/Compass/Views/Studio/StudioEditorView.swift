import CompassCore
import SwiftUI

struct StudioEditorView: View {
  @ObservedObject var state: StudioState
  @Environment(\.colorScheme) private var colorScheme

  private static let highlightFadeSeconds: TimeInterval = 3

  var body: some View {
    if let path = state.openFile,
      let buffer = state.presentationBuffers[path] ?? state.buffers[path]
    {
      VStack(spacing: 0) {
        recentStrip
        breadcrumb(path: path)
        Divider()
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
          let highlightOpacity = fadeOpacity(
            since: buffer.lastChangeAt,
            now: context.date
          )
          let theme =
            colorScheme == .dark
            ? StudioHighlightTheme.dark
            : StudioHighlightTheme.light
          let source = buffer.lines.joined(separator: "\n")
          let highlighted = StudioSyntaxHighlighter.shared.highlightLines(
            source: source,
            path: path,
            theme: theme
          )
          ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
              LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(buffer.lines.enumerated()), id: \.offset) { index, line in
                  let lineNumber = index + 1
                  let attributed: AttributedString = {
                    if index < highlighted.count {
                      return highlighted[index]
                    }
                    return AttributedString(line.isEmpty ? " " : line)
                  }()
                  HStack(spacing: 0) {
                    Text("\(lineNumber)")
                      .font(.system(.caption, design: .monospaced))
                      .foregroundStyle(
                        buffer.highlightedLines.contains(lineNumber)
                          ? Color.green.opacity(0.85)
                          : Color(nsColor: .tertiaryLabelColor)
                      )
                      .frame(width: 44, alignment: .trailing)
                      .padding(.trailing, 10)
                      .background(
                        buffer.highlightedLines.contains(lineNumber)
                          ? Color.green.opacity(highlightOpacity * 0.6)
                          : Color.clear
                      )
                    Text(attributed.characters.isEmpty ? AttributedString(" ") : attributed)
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
              .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: buffer.scrollTour?.id) {
              performScrollTour(proxy: proxy, buffer: buffer)
            }
            .onChange(of: buffer.scrollToLine) {
              if buffer.scrollTour == nil {
                scrollToRevealedLine(proxy: proxy, buffer: buffer)
              }
            }
            .onChange(of: state.isTypewriting) {
              if buffer.scrollTour == nil {
                scrollToRevealedLine(proxy: proxy, buffer: buffer)
              }
            }
            .onAppear {
              if buffer.scrollTour != nil {
                performScrollTour(proxy: proxy, buffer: buffer)
              } else {
                scrollToRevealedLine(proxy: proxy, buffer: buffer)
              }
            }
          }
        }
        footer(path: path, buffer: buffer)
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

  @ViewBuilder
  private var recentStrip: some View {
    if !state.recentPaths.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(state.recentPaths.reversed(), id: \.self) { path in
            Button {
              state.peek(path)
            } label: {
              Text((path as NSString).lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                  RoundedRectangle(cornerRadius: 4)
                    .fill(
                      path == state.openFile
                        ? Color.accentColor.opacity(0.22)
                        : Color.secondary.opacity(0.12)
                    )
                )
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
      }
      Divider()
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
      if !state.followAgent {
        Button("Follow") {
          state.resumeFollowing()
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.borderless)
      }
      if state.isTypewriting {
        Image(systemName: "character.cursor.ibeam")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .help("Agent edit playing back")
      }
      Image(systemName: "lock.fill")
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .help("Read-only — the Studio editor mirrors what the agent does.")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
  }

  private func footer(path: String, buffer: StudioState.FileBuffer) -> some View {
    HStack(spacing: 10) {
      Text(languageLabel(for: path))
        .foregroundStyle(.secondary)
      Text("\(buffer.lines.count) lines")
        .foregroundStyle(.tertiary)
      if let truth = state.buffers[path], truth.lines.count != buffer.lines.count {
        Text("playing back…")
          .foregroundStyle(.tertiary)
      }
      Spacer(minLength: 0)
    }
    .font(.caption2.monospaced())
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
  }

  private func languageLabel(for path: String) -> String {
    if let language = CodemapLanguage.forRelativePath(path) {
      return language.displayName
    }
    let ext = (path as NSString).pathExtension.lowercased()
    if ext.isEmpty { return "Plain text" }
    return ext.uppercased()
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
      withAnimation(.easeOut(duration: 0.15)) {
        proxy.scrollTo(line, anchor: .center)
      }
    }
  }

  /// Jump quickly to the read start line, then ease down to the end of the span.
  private func performScrollTour(
    proxy: ScrollViewProxy,
    buffer: StudioState.FileBuffer
  ) {
    guard let tour = buffer.scrollTour else {
      scrollToRevealedLine(proxy: proxy, buffer: buffer)
      return
    }
    let start = tour.startLine
    let end = tour.endLine
    DispatchQueue.main.async {
      // Phase 1: rapid jump to the start of what the agent is reading.
      withAnimation(.easeOut(duration: 0.12)) {
        proxy.scrollTo(start, anchor: .top)
      }
      guard end > start else { return }
      // Phase 2: normal skim to the end of the read range.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
        withAnimation(.easeInOut(duration: skimDuration(from: start, to: end))) {
          proxy.scrollTo(end, anchor: .center)
        }
      }
    }
  }

  private func skimDuration(from start: Int, to end: Int) -> TimeInterval {
    let span = max(end - start, 1)
    // ~short hops stay snappy; long file skims cap around 1.2s.
    return min(1.2, max(0.35, Double(span) / 400.0))
  }
}
