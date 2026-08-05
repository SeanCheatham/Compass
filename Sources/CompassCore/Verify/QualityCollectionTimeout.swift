import Foundation

public enum QualityCollectionTimeout {
  public static func seconds() -> TimeInterval {
    let raw = ProcessInfo.processInfo.environment["COMPASS_QUALITY_COLLECTION_TIMEOUT_MS"]
    guard let raw, let milliseconds = Int(raw), milliseconds > 0 else { return 600 }
    return TimeInterval(milliseconds) / 1000
  }
}
