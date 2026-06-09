import SwiftUI

func reliabilityColor(for severity: PlanReliabilityFeedback.Severity) -> Color {
  switch severity {
  case .warning:
    return .orange
  case .failure:
    return .red
  case .paused:
    return .blue
  }
}

func storageAssessmentColor(for severity: CompassWorkspaceStorageAssessment.Severity) -> Color {
  switch severity {
  case .healthy:
    return .green
  case .info:
    return .blue
  case .warning:
    return .orange
  case .failure:
    return .red
  }
}
