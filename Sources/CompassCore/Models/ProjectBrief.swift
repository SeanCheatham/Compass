import Foundation

public struct ProductRequirement: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var text: String
  public var kind: ProductRequirementKind
  public var proofLevel: RequirementProofLevel

  public enum CodingKeys: String, CodingKey {
    case id
    case text
    case kind
    case proofLevel
    case proofLevelSnake = "proof_level"
  }

  public init(
    id: String = UUID().uuidString.lowercased(),
    text: String,
    kind: ProductRequirementKind = .behavior,
    proofLevel: RequirementProofLevel? = nil
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    self.kind = kind
    self.proofLevel = proofLevel ?? kind.defaultProofLevel
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id =
      (try? container.decodeIfPresent(String.self, forKey: .id))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      ?? UUID().uuidString.lowercased()
    let text =
      (try container.decodeIfPresent(String.self, forKey: .text))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let kindRaw =
      (try? container.decodeIfPresent(String.self, forKey: .kind))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let kind = ProductRequirementKind(rawValue: kindRaw ?? "") ?? .behavior
    let proofRaw =
      (try? container.decodeIfPresent(String.self, forKey: .proofLevel))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      ?? (try? container.decodeIfPresent(String.self, forKey: .proofLevelSnake))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let proof =
      proofRaw.flatMap(RequirementProofLevel.init(rawValue:)) ?? kind.defaultProofLevel
    self.init(id: id.isEmpty ? UUID().uuidString.lowercased() : id, text: text, kind: kind, proofLevel: proof)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(text, forKey: .text)
    try container.encode(kind.rawValue, forKey: .kind)
    try container.encode(proofLevel.rawValue, forKey: .proofLevel)
  }

  public var isEmpty: Bool {
    text.isEmpty
  }
}

public struct ProjectBrief: Codable, Equatable, Sendable {
  public var audience: String
  public var problem: String
  public var productRequirements: [ProductRequirement]

  public static let empty = ProjectBrief(
    audience: "",
    problem: "",
    productRequirements: []
  )

  public static let emptyJSON = """
    {
      "audience" : "",
      "problem" : "",
      "productRequirements" : [

      ]
    }
    """

  public init(
    audience: String = "",
    problem: String = "",
    productRequirements: [ProductRequirement] = []
  ) {
    self.audience = audience.trimmingCharacters(in: .whitespacesAndNewlines)
    self.problem = problem.trimmingCharacters(in: .whitespacesAndNewlines)
    self.productRequirements = productRequirements.filter { !$0.isEmpty }
  }

  public var isEmpty: Bool {
    audience.isEmpty && problem.isEmpty && productRequirements.isEmpty
  }

  public var nonEmptyRequirements: [ProductRequirement] {
    productRequirements.filter { !$0.isEmpty }
  }

  public var hasAudience: Bool { !audience.isEmpty }
  public var hasProblem: Bool { !problem.isEmpty }
  public var hasRequirements: Bool { !nonEmptyRequirements.isEmpty }

  public var isReady: Bool {
    hasAudience && hasProblem && hasRequirements
  }

  /// Trim fields and drop blank requirements before persistence or agent use.
  public func sanitized() -> ProjectBrief {
    ProjectBrief(
      audience: audience,
      problem: problem,
      productRequirements: nonEmptyRequirements
    )
  }

  /// Markdown projection for agent prompts and clipboard handoffs.
  public func renderedMarkdown(maxCharacters: Int = 2_400) -> String {
    var lines: [String] = []

    lines.append("### Audience")
    lines.append(audience.isEmpty ? "_(not set)_" : audience)
    lines.append("")
    lines.append("### Problem")
    lines.append(problem.isEmpty ? "_(not set)_" : problem)
    lines.append("")
    lines.append("### Product Requirements")
    if nonEmptyRequirements.isEmpty {
      lines.append("- _(none)_")
    } else {
      for requirement in nonEmptyRequirements {
        lines.append(
          "- (\(requirement.kind.rawValue)/\(requirement.proofLevel.rawValue)) \(requirement.text) `(id: \(requirement.id))`"
        )
      }
    }

    let joined = lines.joined(separator: "\n")
    guard joined.count > maxCharacters else { return joined }
    guard maxCharacters > 3 else { return String(joined.prefix(maxCharacters)) }
    return String(joined.prefix(maxCharacters - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  /// Compact one-line summary for Plan strategic seeding.
  public func compactSummary(limit: Int = 280) -> String {
    let compact =
      problem
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard compact.count > limit else { return compact }
    guard limit > 3 else { return String(compact.prefix(limit)) }
    return compact.prefix(limit - 3).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  /// Fixture helper when only the problem statement varies.
  public static func problemFocused(
    _ problem: String,
    audience: String = "Compass maintainers",
    requirement: String = "Deliver the requested change with verified repository-local edits.",
    kind: ProductRequirementKind = .behavior,
    proofLevel: RequirementProofLevel? = nil
  ) -> ProjectBrief {
    ProjectBrief(
      audience: audience,
      problem: problem,
      productRequirements: [
        ProductRequirement(text: requirement, kind: kind, proofLevel: proofLevel)
      ]
    )
  }
}
