export interface ToolDetail {
  /** Short one-liner for the collapsed view */
  summary: string;
  /** Key-value pairs shown when expanded */
  full: Record<string, string>;
}

/**
 * Extracts a human-readable summary and full details from a tool_use block's input.
 */
export function extractToolDetail(toolName: string, input: Record<string, unknown>): ToolDetail | undefined {
  switch (toolName) {
    case "Bash": {
      const cmd = input.command as string | undefined;
      if (!cmd) return undefined;
      return {
        summary: truncate(cmd, 60),
        full: {
          command: cmd,
          ...(input.description ? { description: input.description as string } : {}),
          ...(input.timeout ? { timeout: `${input.timeout}ms` } : {}),
        },
      };
    }
    case "Read": {
      const fp = input.file_path as string | undefined;
      if (!fp) return undefined;
      return {
        summary: shortenPath(fp),
        full: {
          file: fp,
          ...(input.offset ? { offset: `line ${input.offset}` } : {}),
          ...(input.limit ? { limit: `${input.limit} lines` } : {}),
        },
      };
    }
    case "Write": {
      const fp = input.file_path as string | undefined;
      if (!fp) return undefined;
      return {
        summary: shortenPath(fp),
        full: { file: fp },
      };
    }
    case "Edit": {
      const fp = input.file_path as string | undefined;
      if (!fp) return undefined;
      const full: Record<string, string> = { file: fp };
      if (input.old_string) full.replacing = truncate(input.old_string as string, 120);
      if (input.replace_all) full.replace_all = "true";
      return { summary: shortenPath(fp), full };
    }
    case "Glob":
      return input.pattern ? {
        summary: input.pattern as string,
        full: {
          pattern: input.pattern as string,
          ...(input.path ? { path: input.path as string } : {}),
        },
      } : undefined;
    case "Grep": {
      const pat = input.pattern as string | undefined;
      if (!pat) return undefined;
      return {
        summary: truncate(pat, 60),
        full: {
          pattern: pat,
          ...(input.path ? { path: input.path as string } : {}),
          ...(input.glob ? { glob: input.glob as string } : {}),
          ...(input.output_mode ? { mode: input.output_mode as string } : {}),
        },
      };
    }
    case "LS":
      return {
        summary: shortenPath((input.path as string) || "."),
        full: { path: (input.path as string) || "." },
      };
    case "Agent":
      return input.description ? {
        summary: truncate(input.description as string, 60),
        full: {
          description: input.description as string,
          ...(input.subagent_type ? { type: input.subagent_type as string } : {}),
        },
      } : undefined;
    case "WebFetch":
      return input.url ? {
        summary: truncate(input.url as string, 60),
        full: { url: input.url as string },
      } : undefined;
    case "WebSearch":
      return input.query ? {
        summary: truncate(input.query as string, 60),
        full: { query: input.query as string },
      } : undefined;
    default:
      // MCP tools — show short tool name + first string value
      if (toolName.startsWith("mcp__")) {
        const shortName = toolName.split("__").pop() || toolName;
        const full: Record<string, string> = {};
        for (const [k, v] of Object.entries(input)) {
          if (typeof v === "string") full[k] = v;
          else if (typeof v === "number" || typeof v === "boolean") full[k] = String(v);
        }
        const firstVal = Object.values(full)[0];
        return {
          summary: firstVal ? `${shortName}: ${truncate(firstVal, 40)}` : shortName,
          full,
        };
      }
      return undefined;
  }
}

function shortenPath(filePath: string): string {
  if (!filePath) return "";
  const parts = filePath.split("/");
  if (parts.length <= 3) return filePath;
  return ".../" + parts.slice(-3).join("/");
}

function truncate(str: string, max: number): string {
  if (str.length <= max) return str;
  return str.slice(0, max) + "...";
}
