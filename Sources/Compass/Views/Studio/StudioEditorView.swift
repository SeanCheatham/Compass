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
        breadcrumb(path: path)
        Divider()
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
        // ScrollViewReader stays outside TimelineView so the 0.5s highlight
        // tick cannot recreate the scroll proxy mid-tour / mid-caret-follow.
        GeometryReader { viewport in
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
                  StudioEditorLineRow(
                    lineNumber: lineNumber,
                    attributed: attributed,
                    isHighlighted: buffer.highlightedLines.contains(lineNumber),
                    lastChangeAt: buffer.lastChangeAt,
                    fadeSeconds: Self.highlightFadeSeconds
                  )
                  .id(lineNumber)
                }
              }
              .padding(.vertical, 6)
              .padding(.trailing, 12)
              // Bidirectional ScrollView otherwise sizes to the widest *visible*
              // LazyVStack row — short/partial lines (typewriter) squash the pane.
              .frame(minWidth: viewport.size.width, alignment: .topLeading)
            }
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
            .onChange(of: path) {
              if buffer.scrollTour != nil {
                performScrollTour(proxy: proxy, buffer: buffer)
              } else {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

  private func scrollToRevealedLine(
    proxy: ScrollViewProxy,
    buffer: StudioState.FileBuffer
  ) {
    guard let line = buffer.scrollToLine, line >= 1 else { return }
    // LazyVStack may not have materialized distant rows on the first pass.
    scrollToLine(proxy: proxy, line: line, anchor: .center, attempts: 2)
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
        // Retry once after layout catches up for long LazyVStack jumps.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
          proxy.scrollTo(end, anchor: .center)
        }
      }
    }
  }

  private func scrollToLine(
    proxy: ScrollViewProxy,
    line: Int,
    anchor: UnitPoint,
    attempts: Int
  ) {
    DispatchQueue.main.async {
      withAnimation(.easeOut(duration: 0.15)) {
        proxy.scrollTo(line, anchor: anchor)
      }
      guard attempts > 1 else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        proxy.scrollTo(line, anchor: anchor)
      }
    }
  }

  private func skimDuration(from start: Int, to end: Int) -> TimeInterval {
    let span = max(end - start, 1)
    // ~short hops stay snappy; long file skims cap around 1.2s.
    return min(1.2, max(0.35, Double(span) / 400.0))
  }
}

/// Line row with its own highlight TimelineView so fade ticks do not rebuild
/// the parent ScrollViewReader / scroll position.
private struct StudioEditorLineRow: View {
  let lineNumber: Int
  let attributed: AttributedString
  let isHighlighted: Bool
  let lastChangeAt: Date
  let fadeSeconds: TimeInterval

  var body: some View {
    HStack(spacing: 0) {
      Text("\(lineNumber)")
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(
          isHighlighted
            ? Color.green.opacity(0.85)
            : Color(nsColor: .tertiaryLabelColor)
        )
        .frame(width: 44, alignment: .trailing)
        .padding(.trailing, 10)
        .background(gutterHighlight)
      Text(attributed.characters.isEmpty ? AttributedString(" ") : attributed)
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        // Keep source on one line; horizontal ScrollView handles overflow.
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 1)
    .background(rowHighlight)
  }

  @ViewBuilder
  private var gutterHighlight: some View {
    if isHighlighted {
      TimelineView(.periodic(from: lastChangeAt, by: 0.5)) { context in
        Color.green.opacity(fadeOpacity(now: context.date) * 0.6)
      }
    } else {
      Color.clear
    }
  }

  @ViewBuilder
  private var rowHighlight: some View {
    if isHighlighted {
      TimelineView(.periodic(from: lastChangeAt, by: 0.5)) { context in
        Color.green.opacity(fadeOpacity(now: context.date))
      }
    } else {
      Color.clear
    }
  }

  private func fadeOpacity(now: Date) -> Double {
    let age = now.timeIntervalSince(lastChangeAt)
    guard age < fadeSeconds else { return 0 }
    return 0.25 * (1 - age / fadeSeconds)
  }
}
