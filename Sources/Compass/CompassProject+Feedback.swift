import AppKit
import CompassCore
import Foundation

@MainActor
extension CompassProject {
  func feedback(_ milestone: NativeFeedbackMilestone) {
    NativeFeedbackService.shared.emit(
      milestone,
      projectName: displayName,
      mode: nativeFeedbackMode
    )
  }

  func feedbackPlanReadinessGate(
    for _: PlanState,
    gate _: PlanReadinessNativeFeedbackGate
  ) {
    NativeFeedbackService.shared.emit(
      .developReady,
      projectName: displayName,
      mode: nativeFeedbackMode
    )
  }
}
