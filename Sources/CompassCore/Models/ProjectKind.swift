import Foundation

/// Top-level Compass project mode.
///
/// - `factory`: Plan → Develop → Verify → Critic → Health (Plan pressure) loop.
/// - `health`: Import a Rust repo and improve it via recon → focused passes → triage
///   (proposed patches committed on a Compass-owned branch).
public enum ProjectKind: String, Codable, Equatable, Sendable, CaseIterable {
  case factory
  case health
}
