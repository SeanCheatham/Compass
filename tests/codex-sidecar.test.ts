import { test } from "node:test";
import assert from "node:assert/strict";

import {
  codexSidecarLabel,
  parseCodexSidecarMode,
} from "../src/agents/codex-sidecar.ts";

test("codex sidecar: parses supported modes", () => {
  assert.equal(parseCodexSidecarMode(undefined), "auto");
  assert.equal(parseCodexSidecarMode("auto"), "auto");
  assert.equal(parseCodexSidecarMode("off"), "off");
  assert.equal(parseCodexSidecarMode("verify-failures"), "verify-failures");
});

test("codex sidecar: parser is case and whitespace tolerant", () => {
  assert.equal(parseCodexSidecarMode(" AUTO "), "auto");
  assert.equal(parseCodexSidecarMode(" OFF "), "off");
});

test("codex sidecar: rejects unknown modes", () => {
  assert.throws(() => parseCodexSidecarMode("always"), /Unknown Codex sidecar mode/);
});

test("codex sidecar: labels supported modes", () => {
  assert.match(codexSidecarLabel("auto"), /verify-failure diagnosis/);
  assert.equal(codexSidecarLabel("off"), "off");
  assert.equal(codexSidecarLabel("verify-failures"), "verify-failures");
});
