import SwiftUI

struct ActivityTab: View {
  @ObservedObject var project: CompassProject
  @State private var section: Section = .now

  enum Section: String, CaseIterable, Identifiable {
    case now = "Now"
    case overview = "Overview"

    var id: Self { self }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Activity section", selection: $section) {
        ForEach(Section.allCases) { section in
          Text(section.rawValue).tag(section)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 280, alignment: .leading)

      switch section {
      case .now:
        LiveTab(project: project)
      case .overview:
        PlanTab(project: project)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
