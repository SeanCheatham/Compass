import AVFoundation
import Combine
import CompassCore
import Foundation

/// Speaks Studio thinking entries aloud. Stays current rather than queuing a
/// backlog: only the newest unspoken entry is kept, and a narration that goes
/// stale while generating is dropped in favor of the newer thought.
@MainActor
final class StudioThinkingSpeechService: NSObject, ObservableObject {
  @Published var isEnabled = false {
    didSet {
      guard !isEnabled else { return }
      queued = nil
      narrationTask?.cancel()
      narrationTask = nil
      busy = false
      synthesizer.stopSpeaking(at: .immediate)
    }
  }

  private let synthesizer = AVSpeechSynthesizer()
  private var cancellable: AnyCancellable?
  private var lastSeenEntryID: UUID?
  private var queued: StudioState.ThinkingEntry?
  private var narrationTask: Task<Void, Never>?
  private var busy = false

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func attach(to state: StudioState) {
    cancellable = state.$thinkingEntries
      .sink { [weak self] entries in
        self?.handle(entries)
      }
  }

  private func handle(_ entries: [StudioState.ThinkingEntry]) {
    guard let last = entries.last else {
      lastSeenEntryID = nil
      return
    }
    guard last.id != lastSeenEntryID else { return }
    lastSeenEntryID = last.id
    guard isEnabled else { return }
    queued = last
    pump()
  }

  private func pump() {
    guard !busy, let next = queued else { return }
    queued = nil
    busy = true
    let entryID = next.id
    narrationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let spoken =
        await StudioThinkingNarrator.narrate(thinking: next.text)
        ?? StudioThinkingNarrator.fallbackSpokenText(for: next.text)
      guard !Task.isCancelled, !spoken.isEmpty else {
        self.finishUtterance()
        return
      }
      // A newer thought arrived while generating — drop the stale narration.
      if self.queued != nil, self.queued?.id != entryID {
        self.finishUtterance()
        return
      }
      let utterance = AVSpeechUtterance(string: spoken)
      PreferredSpeechVoice.configure(utterance)
      self.synthesizer.speak(utterance)
    }
  }

  private func finishUtterance() {
    busy = false
    pump()
  }
}

extension StudioThinkingSpeechService: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.finishUtterance()
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.finishUtterance()
    }
  }
}
