import { test } from "node:test";
import assert from "node:assert/strict";

import {
  codexSidecarLabel,
  getDefaultCodexTimeoutsForTest,
  getCodexOptionsForTest,
  getCodexSidecarTimeoutMsForTest,
  isCodexUnavailableErrorForTest,
  parseCodexSidecarMode,
} from "../src/agents/codex-sidecar.ts";

test("codex sidecar: parses supported modes", () => {
  assert.equal(parseCodexSidecarMode(undefined), "auto");
  assert.equal(parseCodexSidecarMode("auto"), "auto");
  assert.equal(parseCodexSidecarMode("off"), "off");
  assert.equal(parseCodexSidecarMode("verify-failures"), "verify-failures");
  assert.equal(parseCodexSidecarMode("diff-review"), "diff-review");
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
  assert.equal(codexSidecarLabel("diff-review"), "diff-review");
});

test("codex sidecar: uses SDK default binary discovery without an override", () => {
  assert.deepEqual(getCodexOptionsForTest({}), {});
});

test("codex sidecar: preserves explicit binary override for the SDK", () => {
  assert.deepEqual(
    getCodexOptionsForTest({ COMPASS_CODEX_BIN: " /custom/codex " }),
    { codexPathOverride: "/custom/codex" }
  );
});

test("codex sidecar: detects unavailable SDK binary errors", () => {
  assert.equal(
    isCodexUnavailableErrorForTest(
      new Error("Unable to locate Codex CLI binaries. Ensure @openai/codex is installed.")
    ),
    true
  );
  assert.equal(
    isCodexUnavailableErrorForTest(
      Object.assign(new Error("spawn codex ENOENT"), { code: "ENOENT" })
    ),
    true
  );
});

test("codex sidecar: does not treat regular SDK failures as unavailable", () => {
  assert.equal(isCodexUnavailableErrorForTest(new Error("Codex Exec exited with code 1")), false);
});

test("codex sidecar: timeout parser uses caller default when unset or invalid", () => {
  assert.equal(getCodexSidecarTimeoutMsForTest(300_000, {}), 300_000);
  assert.equal(
    getCodexSidecarTimeoutMsForTest(300_000, {
      COMPASS_CODEX_SIDECAR_TIMEOUT_MS: "-1",
    }),
    300_000
  );
  assert.equal(
    getCodexSidecarTimeoutMsForTest(300_000, {
      COMPASS_CODEX_SIDECAR_TIMEOUT_MS: "nope",
    }),
    300_000
  );
});

test("codex sidecar: timeout parser honors explicit override", () => {
  assert.equal(
    getCodexSidecarTimeoutMsForTest(300_000, {
      COMPASS_CODEX_SIDECAR_TIMEOUT_MS: "600000",
    }),
    600_000
  );
});

test("codex sidecar: default timeouts are tuned by sidecar task", () => {
  assert.deepEqual(getDefaultCodexTimeoutsForTest(), {
    verifyMs: 120_000,
    diffReviewMs: 900_000,
  });
});
