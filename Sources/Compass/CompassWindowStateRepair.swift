import Foundation
import CompassCore

enum CompassWindowStateRepair {
  private static let splitViewPrefix = "NSSplitView Subview Frames "
  private static let windowFramePrefix = "NSWindow Frame "
  private static let navigationSplitSuffix = ", SidebarNavigationSplitView"
  private static let corruptedHeightMultiplier = 1.25

  static func repairNavigationSplitViewFrames(defaults: UserDefaults = .standard) {
    for key in defaults.dictionaryRepresentation().keys {
      guard key.hasPrefix(splitViewPrefix),
        key.hasSuffix(navigationSplitSuffix),
        shouldRemoveNavigationSplitFrame(key: key, defaults: defaults)
      else {
        continue
      }

      defaults.removeObject(forKey: key)
    }
  }

  static func frameHeight(from frameString: String) -> Double? {
    let parts =
      frameString
      .split { $0 == "," || $0 == " " }
      .compactMap { Double($0) }
    guard parts.count >= 4 else { return nil }
    return parts[3]
  }

  private static func shouldRemoveNavigationSplitFrame(
    key: String,
    defaults: UserDefaults
  ) -> Bool {
    guard let splitFrames = defaults.array(forKey: key) as? [String],
      !splitFrames.isEmpty,
      let windowHeight = windowHeight(forSplitFrameKey: key, defaults: defaults),
      windowHeight > 0
    else {
      return false
    }

    let maximumReasonableHeight = windowHeight * corruptedHeightMultiplier
    return
      splitFrames
      .compactMap(frameHeight)
      .contains { $0 > maximumReasonableHeight }
  }

  private static func windowHeight(
    forSplitFrameKey key: String,
    defaults: UserDefaults
  ) -> Double? {
    guard let identifier = splitViewIdentifier(from: key) else { return nil }
    let windowKey = "\(windowFramePrefix)\(identifier)"
    guard let windowFrame = defaults.string(forKey: windowKey) else { return nil }
    return frameHeight(from: windowFrame)
  }

  private static func splitViewIdentifier(from key: String) -> String? {
    guard key.hasPrefix(splitViewPrefix),
      key.hasSuffix(navigationSplitSuffix)
    else {
      return nil
    }

    let start = key.index(key.startIndex, offsetBy: splitViewPrefix.count)
    let end = key.index(key.endIndex, offsetBy: -navigationSplitSuffix.count)
    guard start < end else { return nil }
    return String(key[start..<end])
  }
}
