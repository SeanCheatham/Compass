import AVFoundation
import Foundation
import UserNotifications

enum NativeFeedbackMode: String, CaseIterable, Codable, Identifiable {
    case off
    case notifications
    case speechAndNotifications = "speech_and_notifications"

    var id: Self { self }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = NativeFeedbackMode(rawValue: rawValue) ?? .notifications
    }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .notifications:
            return "Notifications"
        case .speechAndNotifications:
            return "Speech + Notifications"
        }
    }

    var systemImage: String {
        switch self {
        case .off:
            return "bell.slash"
        case .notifications:
            return "bell"
        case .speechAndNotifications:
            return "speaker.wave.2"
        }
    }

    var sendsNotifications: Bool {
        switch self {
        case .off:
            return false
        case .notifications, .speechAndNotifications:
            return true
        }
    }

    var speaks: Bool {
        self == .speechAndNotifications
    }
}

enum NativeFeedbackMilestone: String {
    case planAccepted
    case developStarted
    case verifyPassed
    case postChecksFailed
    case commitsPromoted
    case paused
    case stopped
    case noImmediateWork
}

@MainActor
final class NativeFeedbackService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NativeFeedbackService()

    private let notificationCenter: UNUserNotificationCenter?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var authorizationRequested = false
    private var notificationsAllowed = false
    private var recentMilestones: [String: Date] = [:]
    private let duplicateWindow: TimeInterval = 8

    private override init() {
        notificationCenter = Self.supportsUserNotifications ? UNUserNotificationCenter.current() : nil

        super.init()
        notificationCenter?.delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func prepare() {
        Task { @MainActor in
            await requestNotificationAuthorizationIfNeeded()
        }
    }

    func applyModeChange(_ mode: NativeFeedbackMode) {
        if mode == .off {
            speechSynthesizer.stopSpeaking(at: .immediate)
        } else {
            prepare()
        }
    }

    func emit(_ milestone: NativeFeedbackMilestone, projectName: String, mode: NativeFeedbackMode) {
        guard mode != .off else { return }

        let projectName = sanitizedProjectName(projectName)
        let dedupeKey = "\(projectName)|\(milestone.rawValue)"
        let now = Date()
        if let last = recentMilestones[dedupeKey], now.timeIntervalSince(last) < duplicateWindow {
            return
        }

        recentMilestones[dedupeKey] = now
        pruneRecentMilestones(now: now)

        let content = NativeFeedbackContent(milestone: milestone, projectName: projectName)
        if mode.sendsNotifications {
            Task { @MainActor in
                await deliverNotification(content)
            }
        }
        if mode.speaks {
            speak(content.spokenPhrase)
        }
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        guard !authorizationRequested else { return }
        authorizationRequested = true

        guard let notificationCenter else {
            notificationsAllowed = false
            return
        }

        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsAllowed = true
        case .denied:
            notificationsAllowed = false
        case .notDetermined:
            notificationsAllowed = (try? await notificationCenter.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            notificationsAllowed = false
        }
    }

    private func deliverNotification(_ content: NativeFeedbackContent) async {
        await requestNotificationAuthorizationIfNeeded()
        guard notificationsAllowed, let notificationCenter else { return }

        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default

        let request = UNNotificationRequest(
            identifier: "compass-native-\(UUID().uuidString)",
            content: notification,
            trigger: nil
        )
        try? await notificationCenter.add(request)
    }

    private func speak(_ phrase: String) {
        guard !speechSynthesizer.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 0.8
        speechSynthesizer.speak(utterance)
    }

    private func pruneRecentMilestones(now: Date) {
        recentMilestones = recentMilestones.filter { now.timeIntervalSince($0.value) < 60 }
    }

    private func sanitizedProjectName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Compass project" }
        return String(trimmed.prefix(48))
    }

    // UserNotifications asserts for SwiftPM-launched executables outside an app bundle.
    private static var supportsUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}

private struct NativeFeedbackContent {
    var title: String
    var body: String
    var spokenPhrase: String

    init(milestone: NativeFeedbackMilestone, projectName: String) {
        switch milestone {
        case .planAccepted:
            title = "\(projectName): Plan accepted"
            body = "Compass has accepted the next plan."
            spokenPhrase = "\(projectName). Plan accepted."
        case .developStarted:
            title = "\(projectName): Develop started"
            body = "Codex is working on the selected plan."
            spokenPhrase = "\(projectName). Develop started."
        case .verifyPassed:
            title = "\(projectName): Verify passed"
            body = "The verify command passed."
            spokenPhrase = "\(projectName). Verify passed."
        case .postChecksFailed:
            title = "\(projectName): Post-checks failed"
            body = "Compass needs another pass before promotion."
            spokenPhrase = "\(projectName). Post-checks failed."
        case .commitsPromoted:
            title = "\(projectName): Commits promoted"
            body = "Develop changes reached the main worktree."
            spokenPhrase = "\(projectName). Commits promoted."
        case .paused:
            title = "\(projectName): Paused"
            body = "Compass is waiting at a gate."
            spokenPhrase = "\(projectName). Paused."
        case .stopped:
            title = "\(projectName): Stopped"
            body = "The current Compass run stopped."
            spokenPhrase = "\(projectName). Stopped."
        case .noImmediateWork:
            title = "\(projectName): No immediate work"
            body = "Plan returned no ready next task."
            spokenPhrase = "\(projectName). No immediate work."
        }
    }
}
