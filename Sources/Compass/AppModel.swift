import AppKit
import Foundation

/// Top-level workspace selection driven by the sidebar.
///
/// The sidebar has two kinds of entries: the singleton Runtime section
/// (hosting the container runtime status view)
/// and the per-project list. `WorkspaceSelection` lets the detail pane
/// swap between them without losing track of which project was last
/// viewed.
enum WorkspaceSelection: Equatable {
  case runtime
  case project(UUID)

  var projectID: UUID? {
    if case .project(let id) = self { return id }
    return nil
  }

  var isSandbox: Bool {
    if case .runtime = self { return true }
    return false
  }
}

@MainActor
final class AppModel: ObservableObject {
  @Published var projects: [CompassProject] = []
  @Published var selectedProjectID: UUID?
  @Published var workspaceSelection: WorkspaceSelection = .runtime
  @Published var modelOverride = ""
  @Published private(set) var agentSettings: AgentRuntimeSettings
  @Published private(set) var runtimeFeatureFlags: CompassRuntimeFeatureFlags
  private let agentSettingsStore: AgentSettingsStore
  @Published var errorMessage: String?

  init(
    agentSettingsStore: AgentSettingsStore = AgentSettingsStore()
  ) {
    self.agentSettingsStore = agentSettingsStore
    self.agentSettings = agentSettingsStore.load()
    self.runtimeFeatureFlags = CompassRuntimeFeatureFlags()
  }

  // MARK: - Agent settings setters

  func setAgentContextWindowTokens(_ tokens: Int) {
    agentSettingsStore.setContextWindowTokens(tokens)
    agentSettings = agentSettingsStore.load()
  }

  var selectedProject: CompassProject? {
    projects.first { $0.id == selectedProjectID }
  }

  /// Switches the detail pane to the runtime section.
  func selectSandbox() {
    workspaceSelection = .runtime
    errorMessage = nil
  }

  func bootstrap() async {
    runtimeFeatureFlags = CompassRuntimeFeatureFlags()

    projects = KnownProjectStore.load().map(CompassProject.init(record:))
    selectedProjectID = projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.first?.id
    if let id = selectedProjectID {
      workspaceSelection = .project(id)
    } else {
      workspaceSelection = .runtime
    }

    if projects.isEmpty {
      errorMessage = nil
    } else {
      for project in projects {
        await project.refresh()
      }
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

  func createTesseraProject() async {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.canSelectHiddenExtension = false
    panel.isExtensionHidden = true
    panel.nameFieldStringValue = "CompassTesseraApp"
    panel.message = "Create a Tessera app for Compass to evolve"
    panel.prompt = "Create"

    guard panel.runModal() == .OK, let url = panel.url else { return }
    let projectURL = url.standardizedFileURL

    do {
      try await Self.initializeGeneratedTesseraProject(at: projectURL)
      let project = upsertProject(repoURL: projectURL)
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
        workspaceSelection = .runtime
      }
    }
    saveProjects()
  }

  func playSelectedProject() async {
    guard let selectedProject else { return }
    await selectedProject.play(agentSettings: agentSettings, modelOverride: modelOverride)
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

    let project = CompassProject(
      repoURL: standardized,
      hostXcodeBuildTestEnabled: false
    )
    projects.insert(project, at: 0)
    saveProjects()
    return project
  }

  static func initializeGeneratedTesseraProject(at url: URL) async throws {
    let projectURL = url.standardizedFileURL
    try ensureCreatableProjectDirectory(projectURL)
    try TesseraProjectScaffold.write(
      to: projectURL,
      options: TesseraProjectScaffold.Options(projectName: projectURL.lastPathComponent)
    )
    let workspace = CompassWorkspace(repoURL: projectURL)
    try workspace.initialize()
    try ForgeProfileService.writeRecord(
      ForgeProfileRecord(profile: .tesseraApp, version: ForgeProfileRecord.currentVersion),
      workspace: workspace
    )
    try await initializeGeneratedTesseraGitRepository(at: projectURL)
  }

  private static func ensureCreatableProjectDirectory(_ url: URL) throws {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      guard isDirectory.boolValue else {
        throw AppModelError.internalInvariant("Cannot create a Tessera app over a file.")
      }
      let children = try fm.contentsOfDirectory(atPath: url.path)
      guard children.isEmpty else {
        throw AppModelError.internalInvariant(
          "Choose an empty folder or a new folder name for the Tessera app.")
      }
    } else {
      try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }

  private static func initializeGeneratedTesseraGitRepository(at url: URL) async throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.appending(path: ".git").path) {
      let initResult = try await ProcessRunner.runEnv(
        "git",
        ["init", "-q"],
        workingDirectory: url
      )
      guard initResult.exitCode == 0 else {
        throw AppModelError.internalInvariant(
          "git init failed: \(processErrorDetail(initResult))")
      }
      _ = try await ProcessRunner.runEnv("git", ["branch", "-M", "main"], workingDirectory: url)
    }

    let addResult = try await ProcessRunner.runEnv("git", ["add", "."], workingDirectory: url)
    guard addResult.exitCode == 0 else {
      throw AppModelError.internalInvariant(
        "git add failed: \(processErrorDetail(addResult))")
    }

    let status = try await ProcessRunner.runEnv(
      "git",
      ["status", "--porcelain"],
      workingDirectory: url
    )
    guard !status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    let commitResult = try await ProcessRunner.runEnv(
      "git",
      [
        "-c", "user.email=compass@example.invalid",
        "-c", "user.name=Compass",
        "commit", "-q", "-m", "Create Tessera app scaffold",
      ],
      workingDirectory: url
    )
    guard commitResult.exitCode == 0 else {
      throw AppModelError.internalInvariant(
        "git commit failed: \(processErrorDetail(commitResult))")
    }
  }

  private static func processErrorDetail(_ result: ProcessResult) -> String {
    let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if !stderr.isEmpty { return stderr }
    let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return stdout.isEmpty ? "exit \(result.exitCode)" : stdout
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
