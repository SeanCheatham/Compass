import Foundation
import Testing

@testable import Compass

struct CompassWindowStateRepairTests: ~Copyable {
  private var defaults: UserDefaults!
  private var suiteName: String!

  init() throws {
    suiteName = "compass.test.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }

  @Test func testFrameHeightParsesWindowAndSplitFrameStrings() throws {
    #expect(CompassWindowStateRepair.frameHeight(from: "26 115 1443 812 0 0 1512 949 ") == 812)
    #expect(
      CompassWindowStateRepair.frameHeight(
        from: "0.000000, 0.000000, 318.000000, 1611.500000, NO, NO")
        == 1611.5)
  }

  @Test func testRepairRemovesCorruptedNavigationSplitFrame() throws {
    let identifier =
      "SwiftUI.ModifiedContent<Compass.ContentView, SwiftUI._FlexFrameLayout>-1-AppWindow-1"
    let splitKey = splitFrameKey(identifier: identifier)
    let windowKey = windowFrameKey(identifier: identifier)

    defaults.set("26 115 1443 812 0 0 1512 949 ", forKey: windowKey)
    defaults.set(
      [
        "0.000000, 0.000000, 318.000000, 1611.500000, NO, NO",
        "0.000000, 0.000000, 1443.000000, 1611.500000, NO, NO",
      ],
      forKey: splitKey
    )

    CompassWindowStateRepair.repairNavigationSplitViewFrames(defaults: defaults)

    #expect(defaults.object(forKey: splitKey) == nil)
    #expect(defaults.string(forKey: windowKey) != nil)
  }

  @Test func testRepairKeepsSaneNavigationSplitFrame() throws {
    let identifier =
      "SwiftUI.ModifiedContent<Compass.ContentView, SwiftUI._FlexFrameLayout>-1-AppWindow-1"
    let splitKey = splitFrameKey(identifier: identifier)

    defaults.set("26 115 1443 812 0 0 1512 949 ", forKey: windowFrameKey(identifier: identifier))
    defaults.set(
      [
        "0.000000, 0.000000, 318.000000, 812.000000, NO, NO",
        "318.000000, 0.000000, 1125.000000, 812.000000, NO, NO",
      ],
      forKey: splitKey
    )

    CompassWindowStateRepair.repairNavigationSplitViewFrames(defaults: defaults)

    #expect(defaults.array(forKey: splitKey) as? [String] != nil)
  }

  @Test func testRepairIgnoresOtherSplitViews() throws {
    let splitKey = "NSSplitView Subview Frames unrelated"
    defaults.set(
      ["0.000000, 0.000000, 318.000000, 1611.500000, NO, NO"],
      forKey: splitKey
    )

    CompassWindowStateRepair.repairNavigationSplitViewFrames(defaults: defaults)

    #expect(defaults.array(forKey: splitKey) as? [String] != nil)
  }

  private func splitFrameKey(identifier: String) -> String {
    "NSSplitView Subview Frames \(identifier), SidebarNavigationSplitView"
  }

  private func windowFrameKey(identifier: String) -> String {
    "NSWindow Frame \(identifier)"
  }
}
