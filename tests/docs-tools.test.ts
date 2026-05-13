import { test } from "node:test";
import assert from "node:assert/strict";

import {
  readBuiltinDoc,
  searchBuiltinDocs,
} from "../src/mcp/docs-tools.ts";

test("docs tools: search finds built-in quality guidance", async () => {
  const result = await searchBuiltinDocs("quality verification shell commands");
  assert.match(result, /software-quality/);
  assert.match(result, /Software Quality/);
});

test("docs tools: read returns complete markdown for a known doc id", async () => {
  const result = await readBuiltinDoc("testing-strategy");
  assert.equal(result.ok, true);
  assert.match(result.text, /^# Testing Strategy/m);
  assert.match(result.text, /deterministic fake agents/i);
});

test("docs tools: read reports available ids for an unknown doc", async () => {
  const result = await readBuiltinDoc("missing-doc");
  assert.equal(result.ok, false);
  assert.match(result.text, /Unknown doc id/);
  assert.match(result.text, /software-quality/);
});
