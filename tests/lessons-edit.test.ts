import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  editLessons,
  ensureWorkspaceExists,
  getWorkspaceConfig,
  readLessons,
  writeLessons,
} from "../src/mcp/utils/workspace.ts";

async function withWorkspace(
  fn: (config: ReturnType<typeof getWorkspaceConfig>) => Promise<void>
): Promise<void> {
  const dir = await mkdtemp(join(tmpdir(), "compass-lessons-edit-"));
  const config = getWorkspaceConfig(dir);
  await ensureWorkspaceExists(config);
  try {
    await fn(config);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

test("editLessons replaces a single exact match", async () => {
  await withWorkspace(async (config) => {
    await writeLessons(config, "- keep\n- old\n");

    const result = await editLessons(config, {
      find: "- old\n",
      replace: "- new\n",
    });

    assert.equal(result.replacements, 1);
    assert.equal(await readLessons(config), "- keep\n- new\n");
  });
});

test("editLessons rejects ambiguous matches unless replaceAll is true", async () => {
  await withWorkspace(async (config) => {
    await writeLessons(config, "- repeat\n- repeat\n");

    await assert.rejects(
      editLessons(config, { find: "- repeat\n", replace: "- once\n" }),
      /matched 2 times/
    );

    const result = await editLessons(config, {
      find: "- repeat\n",
      replace: "- all\n",
      replaceAll: true,
    });
    assert.equal(result.replacements, 2);
    assert.equal(await readLessons(config), "- all\n- all\n");
  });
});

test("editLessons can initialize an empty lessons file", async () => {
  await withWorkspace(async (config) => {
    const result = await editLessons(config, {
      find: "",
      replace: "- first lesson\n",
    });

    assert.equal(result.replacements, 1);
    assert.equal(await readLessons(config), "- first lesson\n");
  });
});

test("editLessons rejects empty find when lessons are non-empty", async () => {
  await withWorkspace(async (config) => {
    await writeLessons(config, "- existing\n");

    await assert.rejects(
      editLessons(config, { find: "", replace: "- replacement\n" }),
      /empty find/
    );
  });
});
