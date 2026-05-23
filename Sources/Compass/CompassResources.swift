import Foundation

/// Bundle accessor that works for both build environments.
///
/// `Bundle.module` is synthesized only for SwiftPM targets that declare
/// `.process("Resources")`. The Xcode app target uses `Bundle.main`
/// because resources land directly in `Compass.app/Contents/Resources/`.
enum CompassResources {
  static var bundle: Bundle {
    #if SWIFT_PACKAGE
      return .module
    #else
      return .main
    #endif
  }
}
