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

enum NativeFeedbackMilestone: String, CaseIterable {
    case planAccepted
    case developStarted
    case verifyStarted
    case verifyPassed
    case developRetrying
    case postChecksFailed
    case commitsPromoted
    case paused
    case stopped
    case noImmediateWork
}

struct NativeFeedbackModeMenuItem: Identifiable, Equatable {
    static let descriptionLimit = 140
    static let permissionHintLimit = 140

    var mode: NativeFeedbackMode
    var title: String
    var systemImage: String
    var isSelected: Bool
    var description: String
    var permissionHint: String

    var id: NativeFeedbackMode { mode }
}

struct NativeFeedbackModeMenu: Equatable {
    var projectName: String
    var labelSystemImage: String
    var helpText: String
    var items: [NativeFeedbackModeMenuItem]

    init(selectedMode: NativeFeedbackMode, projectName rawProjectName: String = "Compass project") {
        let projectName = NativeFeedbackContent.sanitizedProjectName(rawProjectName)
        self.projectName = projectName
        labelSystemImage = selectedMode.systemImage
        helpText = "Feedback: \(selectedMode.title)"
        items = NativeFeedbackMode.allCases.map { mode in
            NativeFeedbackModeMenuItem(
                mode: mode,
                title: mode.title,
                systemImage: selectedMode == mode ? "checkmark" : mode.systemImage,
                isSelected: selectedMode == mode,
                description: Self.description(for: mode, projectName: projectName),
                permissionHint: Self.permissionHint(for: mode, projectName: projectName)
            )
        }
    }

    private static func description(for mode: NativeFeedbackMode, projectName: String) -> String {
        let copy: String
        switch mode {
        case .off:
            copy = "No macOS alerts or spoken updates for \(projectName)."
        case .notifications:
            copy = "Show macOS banners when \(projectName) reaches plan, verify, or promotion milestones."
        case .speechAndNotifications:
            copy = "Speak updates for \(projectName) and show macOS banners for key milestones."
        }
        return bounded(copy, limit: NativeFeedbackModeMenuItem.descriptionLimit)
    }

    private static func permissionHint(for mode: NativeFeedbackMode, projectName: String) -> String {
        let copy: String
        switch mode {
        case .off:
            copy = "No notification permission request for \(projectName)."
        case .notifications:
            copy = "Compass asks notification permission for \(projectName) only when enabled or first delivered."
        case .speechAndNotifications:
            copy = "Speech uses local audio; notifications for \(projectName) ask permission only when needed."
        }
        return bounded(copy, limit: NativeFeedbackModeMenuItem.permissionHintLimit)
    }

    private static func bounded(_ rawValue: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard rawValue.count > limit else { return rawValue }
        return String(rawValue.prefix(limit))
    }
}

struct NativeFeedbackContent: Equatable {
    static let projectNameLimit = 48
    static let titleLimit = 80
    static let bodyLimit = 120
    static let spokenPhraseLimit = 120

    var projectName: String
    var title: String
    var body: String
    var spokenPhrase: String

    init(milestone: NativeFeedbackMilestone, projectName rawProjectName: String) {
        let projectName = Self.sanitizedProjectName(rawProjectName)
        self.projectName = projectName

        let title: String
        let body: String
        let spokenPhrase: String

        switch milestone {
        case .planAccepted:
            title = "\(projectName): Plan accepted"
            body = "Compass has accepted the next plan."
            spokenPhrase = "\(projectName). Plan accepted."
        case .developStarted:
            title = "\(projectName): Develop started"
            body = "Codex is working on the selected plan."
            spokenPhrase = "\(projectName). Develop started."
        case .verifyStarted:
            title = "\(projectName): Verify started"
            body = "Compass is running the verify command."
            spokenPhrase = "\(projectName). Verify started."
        case .verifyPassed:
            title = "\(projectName): Verify passed"
            body = "The verify command passed."
            spokenPhrase = "\(projectName). Verify passed."
        case .developRetrying:
            title = "\(projectName): Develop retrying"
            body = "Post-checks need another Codex pass."
            spokenPhrase = "\(projectName). Develop retrying."
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

        self.title = Self.boundedText(title, limit: Self.titleLimit)
        self.body = Self.boundedText(body, limit: Self.bodyLimit)
        self.spokenPhrase = Self.boundedText(spokenPhrase, limit: Self.spokenPhraseLimit)
    }

    static func sanitizedProjectName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Compass project" }
        return String(trimmed.prefix(projectNameLimit))
    }

    private static func boundedText(_ rawValue: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard rawValue.count > limit else { return rawValue }
        return String(rawValue.prefix(limit))
    }
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

        let projectName = NativeFeedbackContent.sanitizedProjectName(projectName)
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

    // UserNotifications asserts for SwiftPM-launched executables outside an app bundle.
    private static var supportsUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}
