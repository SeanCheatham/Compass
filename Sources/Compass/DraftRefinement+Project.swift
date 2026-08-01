import CompassCore
import Foundation

extension DraftRefinementContext {
  @MainActor
  init(project: CompassProject) {
    self.init(
      repoName: project.displayName,
      state: project.state,
      languageProfile: project.languageProfile
    )
  }
}
