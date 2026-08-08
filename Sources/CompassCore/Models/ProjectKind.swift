import Foundation

/// Top-level Compass project mode.
///
/// - `factory`: Plan → Develop → Verify → Critic → Chamber (Plan pressure) loop.
/// - `chamber`: Pure adversarial test-generation hunt over an imported Rust repo.
public enum ProjectKind: String, Codable, Equatable, Sendable, CaseIterable {
  case factory
  case chamber
}
