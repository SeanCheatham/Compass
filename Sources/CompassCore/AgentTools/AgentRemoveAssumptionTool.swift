import Foundation

/// Remove an assumption from active guidance when new evidence makes it stale.
/// The ledger keeps the record as `superseded` so the user can still inspect
/// the history, but active prompts no longer include it.
struct AgentRemoveAssumptionTool: AgentTool {
  static let toolName = "remove_assumption"

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["id"],
      "properties": [
        "id": [
          "type": "string",
          "description":
            "The assumption id to remove. Use the id shown in the assumptions prompt.",
        ],
        "reason": [
          "type": "string",
          "description":
            "Why the assumption is stale, superseded, or no longer useful as guidance.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Mark a stale or superseded assumption as removed so Compass stops injecting it into future prompts while preserving history for review.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }

    let id = args.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else {
      return .failure(.invalidArguments("`id` must be a non-empty string."))
    }
    guard let assumptionsURL = context.assumptionsURL else {
      return .failure(
        "Assumption ledger is unavailable for this run.",
        kind: .ioFailure
      )
    }

    do {
      let record = try AssumptionLedgerStore(url: assumptionsURL).remove(
        id: id,
        comment: args.reason
      )
      return .ok("Removed assumption \(record.id) from active guidance.")
    } catch let error as AssumptionLedgerError {
      return .failure(.invalidArguments(error.localizedDescription))
    } catch {
      return .failure(.ioFailure(error.localizedDescription))
    }
  }
}

private struct Arguments: Decodable {
  var id: String
  var reason: String?

  enum CodingKeys: String, CodingKey {
    case id
    case assumptionID
    case assumptionIDSnake = "assumption_id"
    case assumption
    case reason
    case rationale
    case comment
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try FlexibleModelDecoder.decodeRequiredString(
      from: container,
      preferredKey: .id,
      aliases: [.assumptionID, .assumptionIDSnake, .assumption],
      fieldName: "id"
    )
    reason = try FlexibleModelDecoder.decodeStringIfPresent(
      from: container,
      preferredKey: .reason,
      aliases: [.rationale, .comment]
    )
  }
}
