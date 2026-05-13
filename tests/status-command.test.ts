import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { showStatus } from "../src/cli/commands.ts";
import { getWorkspaceConfig } from "../src/mcp/utils/workspace.ts";
import type { SessionRecord } from "../src/state/sessions.ts";

async function tmpCompassWorkspace(): Promise<{
  dir: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-status-"));
  const config = getWorkspaceConfig(dir);
  await mkdir(config.workspacePath, { recursive: true });
  return { dir, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

async function captureConsoleLog(fn: () => Promise<void>): Promise<string> {
  const lines: string[] = [];
  const orig = console.log;
  console.log = (...args: unknown[]) => {
    lines.push(args.join(" "));
  };
  try {
    await fn();
  } finally {
    console.log = orig;
  }
  return lines.join("\n");
}

function session(
  n: number,
  fields: Partial<SessionRecord> = {}
): SessionRecord {
  return {
    session: n,
    startedAt: n * 1000,
    endedAt: n * 1000 + 1500,
    plan: `Plan ${n}\nmore detail`,
    verify: "npm test",
    beforeSha: null,
    afterSha: null,
    commits: [],
    status: "succeeded",
    notes: [],
    verifyOutput: null,
    feedback: null,
    ...fields,
  };
}

test("showStatus: renders recent persisted sessions with feedback and verify failure tail", async () => {
  const { dir, cleanup } = await tmpCompassWorkspace();
  try {
    const config = getWorkspaceConfig(dir);
    await writeFile(
      config.sessionsRecordPath,
      JSON.stringify(
        [
          session(1, { plan: "old plan" }),
          session(2),
          session(3),
          session(4),
          session(5, {
            status: "failed",
            commits: [
              {
                sha: "abcdef1234567890",
                short: "abcdef1",
                subject: "ship status history",
              },
            ],
            verifyOutput: {
              command: "npm test",
              exitCode: 1,
              tail: "line one\nline two\nfinal failure line",
            },
          }),
          session(6, {
            endedAt: null,
            status: "developing",
            plan: "\nImplement newest thing\nwith details",
            verify: "npm run lint && npm test",
            feedback: "Need Plan to rescope next.\nDetails are visible.",
          }),
        ],
        null,
        2
      ),
      "utf-8"
    );

    const output = await captureConsoleLog(() => showStatus(dir));

    assert.match(output, /--- Sessions ---/);
    assert.match(output, /Latest feedback \(#6\): Need Plan to rescope next\./);
    assert.match(output, /Details are visible\./);
    assert.match(output, /#6 developing/);
    assert.match(output, /Plan: Implement newest thing/);
    assert.match(output, /Verify: npm run lint && npm test/);
    assert.match(output, /#5 failed \(1\.5s\)/);
    assert.match(output, /Commit: abcdef1 ship status history/);
    assert.match(output, /Verify failure: exit 1/);
    assert.match(output, /final failure line/);
    assert.equal(output.includes("#1 succeeded"), false);
    assert.ok(output.indexOf("#6 developing") < output.indexOf("#5 failed"));
  } finally {
    await cleanup();
  }
});

test("showStatus: renders empty sessions section when no records exist", async () => {
  const { dir, cleanup } = await tmpCompassWorkspace();
  try {
    const output = await captureConsoleLog(() => showStatus(dir));
    const sessionsStart = output.indexOf("--- Sessions ---");
    assert.notEqual(sessionsStart, -1);
    assert.match(output.slice(sessionsStart), /--- Sessions ---\n\(none\)/);
  } finally {
    await cleanup();
  }
});
