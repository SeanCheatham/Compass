import AppKit
import Foundation
import Virtualization

/// Top-level workspace selection driven by the sidebar.
///
/// The sidebar has two kinds of entries: the singleton Sandbox section
/// (hosting the shared VM view + first-boot checklist + provisioning UI)
/// and the per-project list. `WorkspaceSelection` lets the detail pane
/// swap between them without losing track of which project was last
/// viewed.
enum WorkspaceSelection: Equatable {
  case sandbox
  case project(UUID)

  var projectID: UUID? {
    if case .project(let id) = self { return id }
    return nil
  }

  var isSandbox: Bool {
    if case .sandbox = self { return true }
    return false
  }
}

@MainActor
final class AppModel: ObservableObject {
  @Published var projects: [CompassProject] = []
  @Published var selectedProjectID: UUID?
  @Published var workspaceSelection: WorkspaceSelection = .sandbox
  @Published var modelOverride = ""
  @Published private(set) var agentSettings: AgentRuntimeSettings
  private let agentSettingsStore: AgentSettingsStore
  @Published var errorMessage: String?

  /// Process-wide shared VM host. Bound to the singleton in
  /// `SharedCompassVM.shared` so every call site sees the same readiness
  /// snapshot. UI binds to its `@Published` properties via the singleton's
  /// own `ObservableObject` surface — there is no per-AppModel mirror.
  let sharedVMHost: SharedCompassVM = SharedCompassVM.shared

  init(agentSettingsStore: AgentSettingsStore = AgentSettingsStore()) {
    self.agentSettingsStore = agentSettingsStore
    self.agentSettings = agentSettingsStore.load()
  }

  // MARK: - Agent settings setters

  func setAgentBaseURL(_ raw: String) {
    agentSettingsStore.setBaseURL(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentAPIKey(_ raw: String) {
    do {
      try agentSettingsStore.setAPIKey(raw)
    } catch {
      errorMessage = "Could not save API key: \(error.localizedDescription)"
    }
    agentSettings = agentSettingsStore.load()
  }

  func setAgentDefaultModel(_ raw: String) {
    agentSettingsStore.setDefaultModel(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentPlanModelOverride(_ raw: String) {
    agentSettingsStore.setPlanModelOverride(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentDevelopModelOverride(_ raw: String) {
    agentSettingsStore.setDevelopModelOverride(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentReflectModelOverride(_ raw: String) {
    agentSettingsStore.setReflectModelOverride(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentCriticModelOverride(_ raw: String) {
    agentSettingsStore.setCriticModelOverride(raw)
    agentSettings = agentSettingsStore.load()
  }

  var selectedProject: CompassProject? {
    projects.first { $0.id == selectedProjectID }
  }

  /// Switches the detail pane to the Sandbox section.
  func selectSandbox() {
    workspaceSelection = .sandbox
    errorMessage = nil
  }

  func bootstrap() async {
    Self.cleanLegacyHostWorktreesCacheIfPresent()

    projects = KnownProjectStore.load().map(CompassProject.init(record:))
    selectedProjectID = projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.first?.id
    if let id = selectedProjectID {
      workspaceSelection = .project(id)
    } else {
      workspaceSelection = .sandbox
    }

    if projects.isEmpty {
      errorMessage = nil
    } else {
      for project in projects {
        await project.refresh()
      }
    }

    // Always-on lifecycle: warm up the shared VM, and if the bundle is
    // already provisioned, kick off the live VZ instance so agent runs
    // against `.sharedVM` projects don't pay a cold-start tax. Failures
    // are non-fatal — readiness captures any problem and Develop falls
    // back to `.host` automatically.
    Task { [weak self] in
      guard let self else { return }
      do {
        try await self.sharedVMHost.warmup()
      } catch {
        self.log(error.localizedDescription, level: .warning)
        return
      }
      if self.sharedVMHost.bundle.existsOnDisk() {
        do {
          try await self.sharedVMHost.start()
        } catch {
          self.log(
            "Shared VM start failed: \(error.localizedDescription)",
            level: .warning
          )
        }
      }
    }
  }

  /// One-shot GC for `~/Library/Caches/Compass/Worktrees/`, the
  /// legacy per-iteration host worktree cache used by the
  /// pre-removal Develop sandbox. Existing dev-* subdirectories are
  /// orphaned now that Compass no longer creates host worktrees;
  /// remove the whole tree on launch so they don't accumulate.
  ///
  /// Best-effort: silently ignores "directory doesn't exist" and
  /// any permission errors. The user can also rm the tree manually.
  private static func cleanLegacyHostWorktreesCacheIfPresent() {
    guard
      let cachesRoot = try? FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      )
    else {
      return
    }
    let legacyRoot =
      cachesRoot
      .appendingPathComponent("Compass", isDirectory: true)
      .appendingPathComponent("Worktrees", isDirectory: true)
    guard FileManager.default.fileExists(atPath: legacyRoot.path) else {
      return
    }
    try? FileManager.default.removeItem(at: legacyRoot)
  }

  /// Surface for AppModel-level log lines (the per-project loggers route
  /// through `CompassProject`). Used by the warmup task.
  private func log(_ message: String, level: LiveLine.Level) {
    // No global log buffer at the AppModel layer today; surface via
    // `errorMessage` for warnings/errors so the UI shows them and discard
    // info lines.
    switch level {
    case .warning, .error:
      errorMessage = message
    default:
      break
    }
  }

  func chooseRepository() async {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "Choose a Git repository for Compass"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let repoURL = try await resolveGitRoot(from: url)
      let project = upsertProject(repoURL: repoURL)
      selectProject(project)
      project.logProjectSelected()
      await project.refresh()
    } catch {
      fail(error)
    }
  }

  func selectProject(_ project: CompassProject) {
    selectedProjectID = project.id
    workspaceSelection = .project(project.id)
    project.lastOpenedAt = Date()
    errorMessage = nil
    saveProjects()
    Task { await project.refresh() }
  }

  func removeProject(_ project: CompassProject) {
    if project.canStop {
      project.stopRun()
    }
    projects.removeAll { $0.id == project.id }
    if selectedProjectID == project.id {
      selectedProjectID = projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.first?.id
      if let newID = selectedProjectID {
        workspaceSelection = .project(newID)
      } else {
        workspaceSelection = .sandbox
      }
    }
    saveProjects()
  }

  func playSelectedProject() async {
    guard let selectedProject else { return }
    await selectedProject.play(agentSettings: agentSettings, modelOverride: modelOverride)
  }

  func runMutationTestingForSelectedProject() async {
    await selectedProject?.runMutationTesting()
  }

  func refreshSelectedProject() async {
    await selectedProject?.refresh()
  }

  private func upsertProject(repoURL: URL) -> CompassProject {
    let standardized = repoURL.standardizedFileURL
    if let existing = projects.first(where: { $0.repoURL.path == standardized.path }) {
      existing.lastOpenedAt = Date()
      saveProjects()
      return existing
    }

    let project = CompassProject(repoURL: standardized)
    projects.insert(project, at: 0)
    saveProjects()
    return project
  }

  private func resolveGitRoot(from url: URL) async throws -> URL {
    let result: ProcessResult
    do {
      result = try await ProcessRunner.runEnv(
        "git",
        ["rev-parse", "--show-toplevel"],
        workingDirectory: url
      )
    } catch {
      throw AppModelError.notGitRepository(url.path)
    }

    guard result.exitCode == 0 else {
      throw AppModelError.notGitRepository(url.path)
    }

    let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !root.isEmpty else {
      throw AppModelError.notGitRepository(url.path)
    }
    return URL(fileURLWithPath: root).standardizedFileURL
  }

  func saveProjects() {
    do {
      try saveProjectsThrowing()
    } catch {
      fail(error)
    }
  }

  func saveProjectsThrowing() throws {
    try KnownProjectStore.save(projects.map(\.record))
  }

  private func fail(_ error: Error) {
    errorMessage = error.localizedDescription
  }
}


enum AppModelError: LocalizedError {
  case noRepositorySelected
  case notGitRepository(String)
  case gitCommandFailed(String)
  case internalInvariant(String)
  case rejectedPlan(String)

  var errorDescription: String? {
    switch self {
    case .noRepositorySelected:
      return "Choose a Git repository before running Compass."
    case .notGitRepository(let path):
      return "\(path) is not inside a Git repository."
    case .gitCommandFailed(let message):
      return message
    case .internalInvariant(let message):
      return message
    case .rejectedPlan(let message):
      return message
    }
  }
}

