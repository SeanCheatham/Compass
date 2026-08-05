import Foundation

/// String-replacement `edit_file` used by the native tool-calling loop.
///
/// The line-range `AgentEditFileTool` exists for small local models that
/// cannot reproduce file content faithfully; capable models edit more
/// reliably by matching exact text. Each edit's `old_string` must occur
/// exactly once in the current file (unless `replace_all` is set), and edits
/// apply in order against the result of the previous edit.
public struct AgentEditFileTextTool: AgentTool {
  public static let toolName = "edit_file"

  public let spec = AgentToolSpec(
    name: toolName,
    description:
      "Edit an existing text file by replacing exact strings. Each edit's old_string must match the current file content exactly (including indentation and newlines) and occur exactly once, unless replace_all is true. Edits apply in order.",
    parameters: AgentToolParametersSchema(literal: [
      "type": "object",
      "properties": [
        "path": [
          "type": "string",
          "description": "Path to the file, relative to the working directory.",
        ],
        "edits": [
          "type": "array",
          "items": [
            "type": "object",
            "properties": [
              "old_string": [
                "type": "string",
                "description":
                  "Exact text to replace. Must occur exactly once unless replace_all is true.",
              ],
              "new_string": [
                "type": "string",
                "description": "Replacement text. Must differ from old_string.",
              ],
              "replace_all": [
                "type": "boolean",
                "description": "Replace every occurrence of old_string. Defaults to false.",
              ],
            ],
            "required": ["old_string", "new_string"],
          ],
          "description": "Ordered string replacements to apply.",
        ],
      ],
      "required": ["path", "edits"],
    ])
  )

  public init() {}

  private struct Arguments: Decodable {
    struct Edit: Decodable {
      let oldString: String
      let newString: String
      let replaceAll: Bool?

      enum CodingKeys: String, CodingKey {
        case oldString = "old_string"
        case newString = "new_string"
        case replaceAll = "replace_all"
      }
    }

    let path: String
    let edits: [Edit]
  }

  public func invoke(arguments: Data, context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(
        .invalidArguments(
          "edit_file expects {\"path\": \"...\", \"edits\": [{\"old_string\": \"...\", \"new_string\": \"...\"}]}. \(error.localizedDescription)"
        ))
    }
    guard !args.edits.isEmpty else {
      return .failure(.invalidArguments("edit_file requires at least one edit."))
    }

    let url: URL
    do {
      url = try context.resolvePath(args.path)
    } catch let error as AgentToolError {
      return .failure(error)
    } catch {
      return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
    }

    let data: Data
    do {
      data = try await context.filesystem.readFile(at: url)
    } catch let error as AgentFilesystemError {
      return .failure(.ioFailure(error.errorDescription ?? "read failed"))
    } catch {
      return .failure(.ioFailure("read failed: \(error.localizedDescription)"))
    }
    guard let original = String(data: data, encoding: .utf8) else {
      return .failure(.ioFailure("\(context.relativize(url)) is not valid UTF-8 text."))
    }

    var content = original
    var appliedSummaries: [String] = []
    for (index, edit) in args.edits.enumerated() {
      guard edit.oldString != edit.newString else {
        return .failure(
          .invalidArguments("edit \(index + 1): old_string and new_string are identical."))
      }
      guard !edit.oldString.isEmpty else {
        return .failure(
          .invalidArguments(
            "edit \(index + 1): old_string is empty. To insert text, include the surrounding anchor lines in old_string."
          ))
      }
      let occurrences = content.components(separatedBy: edit.oldString).count - 1
      if edit.replaceAll == true {
        guard occurrences > 0 else {
          return .failure(
            .invalidArguments(
              "edit \(index + 1): old_string was not found in \(context.relativize(url)). Re-read the file and match its exact current content."
            ))
        }
        content = content.replacingOccurrences(of: edit.oldString, with: edit.newString)
        appliedSummaries.append("edit \(index + 1): replaced \(occurrences) occurrence(s)")
      } else {
        guard occurrences == 1 else {
          let detail =
            occurrences == 0
            ? "old_string was not found in \(context.relativize(url)). Re-read the file and match its exact current content."
            : "old_string occurs \(occurrences) times in \(context.relativize(url)). Include more surrounding context to make it unique, or set replace_all to true."
          return .failure(.invalidArguments("edit \(index + 1): \(detail)"))
        }
        content = content.replacingOccurrences(of: edit.oldString, with: edit.newString)
        appliedSummaries.append("edit \(index + 1): replaced 1 occurrence")
      }
    }

    guard content != original else {
      return .failure(.invalidArguments("edit_file produced no changes."))
    }

    if let rejection = AgentEditSafety.validatePostEdit(
      relativePath: context.relativize(url),
      sourceURL: url,
      originalText: original,
      editedText: content
    ) {
      return .failure(.invalidArguments(rejection))
    }

    do {
      try await context.filesystem.writeFile(Data(content.utf8), at: url)
    } catch let error as AgentFilesystemError {
      return .failure(.ioFailure(error.errorDescription ?? "write failed"))
    } catch {
      return .failure(.ioFailure("write failed: \(error.localizedDescription)"))
    }
    await context.readTracker.markRead(url)

    let oldLines = original.components(separatedBy: "\n").count
    let newLines = content.components(separatedBy: "\n").count
    return .ok(
      """
      Updated \(context.relativize(url)) (\(oldLines) -> \(newLines) lines).
      \(appliedSummaries.joined(separator: "\n"))
      """
    )
  }
}
