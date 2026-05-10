import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, stat, readdir, readFile } from "node:fs/promises";
import { statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  createOutputManager,
  type OutputEvent,
} from "../src/web/output-manager.ts";

async function tmpWorkspace(): Promise<{
  sessionsDir: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-output-"));
  return {
    sessionsDir: dir,
    cleanup: () => rm(dir, { recursive: true, force: true }),
  };
}

function ev(
  type: OutputEvent["type"],
  data: string,
  timestamp: number
): OutputEvent {
  return { type, data, timestamp };
}

function lines(events: OutputEvent[]): string {
  return events.map((e) => JSON.stringify(e)).join("\n") + "\n";
}

test("output-manager rehydrate: loads buffer from existing session-NNN.jsonl on construction", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const e1 = ev("log", "hello", 1);
    const e2 = ev("info", "world", 2);
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([e1, e2]));

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 2);
    assert.deepEqual(buf[0], e1);
    assert.deepEqual(buf[1], e2);
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: merges pre-session.jsonl before session-NNN files in chronological order", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const t1 = ev("log", "pre", 100);
    const t2 = ev("log", "s1", 200);
    const t3 = ev("log", "s2", 300);
    await writeFile(join(sessionsDir, "pre-session.jsonl"), lines([t1]));
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([t2]));
    await writeFile(join(sessionsDir, "session-002.jsonl"), lines([t3]));

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 3);
    assert.deepEqual(
      buf.map((e) => e.timestamp),
      [100, 200, 300]
    );
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: caps buffer at maxBuffer keeping the most recent events", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const events: OutputEvent[] = [];
    for (let i = 0; i < 10; i++) {
      events.push(ev("log", `msg-${i}`, i));
    }
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines(events));

    const om = createOutputManager({ sessionsDir, maxBuffer: 3 });
    const buf = om.getBuffer();
    assert.equal(buf.length, 3);
    assert.deepEqual(
      buf.map((e) => e.timestamp),
      [7, 8, 9]
    );
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: skips malformed JSON lines but keeps valid ones", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const e1 = ev("log", "a", 1);
    const e2 = ev("log", "b", 2);
    const e3 = ev("log", "c", 3);
    const content =
      JSON.stringify(e1) +
      "\n" +
      "not json" +
      "\n" +
      JSON.stringify(e2) +
      "\n" +
      "" +
      "\n" +
      JSON.stringify(e3) +
      "\n";
    await writeFile(join(sessionsDir, "session-001.jsonl"), content);

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 3);
    assert.deepEqual(buf, [e1, e2, e3]);
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: skips lines that don't match the OutputEvent shape", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const valid = ev("log", "ok", 42);
    const content =
      JSON.stringify({}) +
      "\n" +
      JSON.stringify({ type: "log" }) +
      "\n" +
      JSON.stringify({ type: "log", timestamp: "oops", data: "x" }) +
      "\n" +
      // NaN serializes to null in JSON, which fails the typeof === "number"
      // check. Inject the literal NaN through a custom string instead.
      '{"type":"log","timestamp":NaN,"data":"x"}' +
      "\n" +
      JSON.stringify(valid) +
      "\n";
    await writeFile(join(sessionsDir, "session-001.jsonl"), content);

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 1);
    assert.deepEqual(buf[0], valid);
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: tolerates missing sessions dir without throwing", async () => {
  const om = createOutputManager({
    sessionsDir: "/path/that/does/not/exist/compass-test",
  });
  assert.deepEqual(om.getBuffer(), []);
});

test("output-manager rehydrate: buffer empty when no sessionsDir is provided", () => {
  const om = createOutputManager({});
  assert.deepEqual(om.getBuffer(), []);
});

test("output-manager rehydrate: ignores files that don't match the jsonl naming pattern", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const valid = ev("log", "only-one", 5);
    await writeFile(join(sessionsDir, "random.txt"), "garbage");
    await writeFile(
      join(sessionsDir, "session-abc.jsonl"),
      JSON.stringify(ev("log", "should-not-load", 1)) + "\n"
    );
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([valid]));

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 1);
    assert.deepEqual(buf[0], valid);
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: new emissions still go to the buffer after rehydration", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const e1 = ev("log", "from-disk", 1);
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([e1]));

    const om = createOutputManager({ sessionsDir });
    om.log("hello");
    const buf = om.getBuffer();
    assert.equal(buf.length, 2);
    assert.deepEqual(buf[0], e1);
    assert.equal(buf[1].type, "log");
    assert.equal(buf[1].data, "hello");
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: rehydrated events are NOT re-persisted to disk", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const e1 = ev("log", "from-disk", 1);
    const path = join(sessionsDir, "session-001.jsonl");
    await writeFile(path, lines([e1]));
    const sizeBefore = (await stat(path)).size;

    const _om = createOutputManager({ sessionsDir });
    // Let any pending async writes flush — there should be none from
    // rehydration, but we need to wait long enough that we'd catch one.
    await new Promise((r) => setTimeout(r, 50));

    const sizeAfter = (await stat(path)).size;
    assert.equal(sizeAfter, sizeBefore);
  } finally {
    await cleanup();
  }
});

test("output-manager rotate: rotates non-empty pre-session.jsonl on construction", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const e1 = ev("log", "banner", 1);
    const original = JSON.stringify(e1) + "\n";
    await writeFile(join(sessionsDir, "pre-session.jsonl"), original);

    const om = createOutputManager({ sessionsDir });

    const names = await readdir(sessionsDir);
    assert.ok(
      !names.includes("pre-session.jsonl"),
      "pre-session.jsonl should be rotated away"
    );

    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n));
    assert.equal(rotated.length, 1);

    const content = await readFile(join(sessionsDir, rotated[0]), "utf-8");
    assert.equal(content, original);

    const buf = om.getBuffer();
    assert.equal(buf.length, 1);
    assert.deepEqual(buf[0], e1);
  } finally {
    await cleanup();
  }
});

test("output-manager rotate: leaves empty pre-session.jsonl in place (no rotation)", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    await writeFile(join(sessionsDir, "pre-session.jsonl"), "");

    const om = createOutputManager({ sessionsDir });

    // pre-session.jsonl should still exist
    const s = statSync(join(sessionsDir, "pre-session.jsonl"));
    assert.equal(s.size, 0);

    const names = await readdir(sessionsDir);
    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n));
    assert.equal(rotated.length, 0);

    assert.deepEqual(om.getBuffer(), []);
  } finally {
    await cleanup();
  }
});

test("output-manager rotate: treats missing pre-session.jsonl as a no-op (no archive created)", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const om = createOutputManager({ sessionsDir });

    const names = await readdir(sessionsDir);
    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n));
    assert.equal(rotated.length, 0);

    assert.deepEqual(om.getBuffer(), []);
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: sorts rehydrated events by first-event timestamp across rotated + session files", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const oldPre = ev("log", "old-banner", 100);
    const oldSess = ev("log", "old-session-1", 200);
    const newPre = ev("log", "new-banner", 400);
    const newSess = ev("log", "new-session-2", 500);

    await writeFile(
      join(sessionsDir, "pre-session-2026-01-01T00-00-00-000Z.jsonl"),
      lines([oldPre])
    );
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([oldSess]));
    await writeFile(join(sessionsDir, "pre-session.jsonl"), lines([newPre]));
    await writeFile(join(sessionsDir, "session-002.jsonl"), lines([newSess]));

    const om = createOutputManager({ sessionsDir });

    const buf = om.getBuffer();
    assert.deepEqual(
      buf.map((e) => e.timestamp),
      [100, 200, 400, 500]
    );

    const names = await readdir(sessionsDir);
    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n));
    assert.equal(rotated.length, 2);
    assert.ok(!names.includes("pre-session.jsonl"));
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: skips files with no valid events from the buffer entirely", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    // All-malformed rotated archive (no valid events at all)
    const malformed =
      "not json\nstill not json\n{ also not json }\n";
    await writeFile(
      join(sessionsDir, "pre-session-2026-01-01T00-00-00-000Z.jsonl"),
      malformed
    );

    // Valid session file
    const good = ev("log", "good", 50);
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([good]));

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 1);
    assert.equal(buf[0].timestamp, 50);
  } finally {
    await cleanup();
  }
});

test("output-manager gc: keeps the K most recent archives, deletes older ones (lex-by-filename)", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 0; i < 25; i++) {
      const day = String(i + 1).padStart(2, "0");
      const name = `pre-session-2026-01-${day}T00-00-00-000Z.jsonl`;
      await writeFile(
        join(sessionsDir, name),
        lines([ev("log", `r${i}`, i)])
      );
    }

    createOutputManager({ sessionsDir });

    const names = await readdir(sessionsDir);
    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n));
    assert.equal(rotated.length, 20);

    const survivors = rotated.sort();
    for (const name of survivors) {
      const m = name.match(/^pre-session-2026-01-(\d{2})T00-00-00-000Z\.jsonl$/);
      assert.ok(m, `unexpected survivor: ${name}`);
      const day = Number(m![1]);
      assert.ok(day >= 6 && day <= 25, `survivor day out of range: ${day}`);
    }
  } finally {
    await cleanup();
  }
});

test("output-manager gc: respects custom maxPreSessionArchives option", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 0; i < 10; i++) {
      const day = String(i + 1).padStart(2, "0");
      const name = `pre-session-2026-01-${day}T00-00-00-000Z.jsonl`;
      await writeFile(
        join(sessionsDir, name),
        lines([ev("log", `r${i}`, i)])
      );
    }

    createOutputManager({ sessionsDir, maxPreSessionArchives: 3 });

    const names = await readdir(sessionsDir);
    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n)).sort();
    assert.equal(rotated.length, 3);

    const days = rotated.map((n) => {
      const m = n.match(/^pre-session-2026-01-(\d{2})T00-00-00-000Z\.jsonl$/);
      return Number(m![1]);
    });
    assert.deepEqual(days, [8, 9, 10]);
  } finally {
    await cleanup();
  }
});

test("output-manager gc: no-op when at or below the cap", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 0; i < 5; i++) {
      const day = String(i + 1).padStart(2, "0");
      const name = `pre-session-2026-01-${day}T00-00-00-000Z.jsonl`;
      await writeFile(
        join(sessionsDir, name),
        lines([ev("log", `r${i}`, i)])
      );
    }

    createOutputManager({ sessionsDir });

    const names = await readdir(sessionsDir);
    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n));
    assert.equal(rotated.length, 5);
  } finally {
    await cleanup();
  }
});

test("output-manager gc: floors maxPreSessionArchives at 1", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 0; i < 5; i++) {
      const day = String(i + 1).padStart(2, "0");
      const name = `pre-session-2026-01-${day}T00-00-00-000Z.jsonl`;
      await writeFile(
        join(sessionsDir, name),
        lines([ev("log", `r${i}`, i)])
      );
    }

    createOutputManager({ sessionsDir, maxPreSessionArchives: 0 });

    const names = await readdir(sessionsDir);
    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n));
    assert.equal(rotated.length, 1);

    const m = rotated[0].match(/^pre-session-2026-01-(\d{2})T00-00-00-000Z\.jsonl$/);
    assert.ok(m);
    assert.equal(Number(m![1]), 5);
  } finally {
    await cleanup();
  }
});

test("output-manager gc: leaves session-NNN.jsonl and pre-session.jsonl alone", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 0; i < 25; i++) {
      const day = String(i + 1).padStart(2, "0");
      const name = `pre-session-2026-01-${day}T00-00-00-000Z.jsonl`;
      await writeFile(
        join(sessionsDir, name),
        lines([ev("log", `r${i}`, i)])
      );
    }

    const sessEvent = ev("log", "session-content", 42);
    const sessContent = lines([sessEvent]);
    await writeFile(join(sessionsDir, "session-001.jsonl"), sessContent);

    const preEvent = ev("log", "active-pre", 99);
    await writeFile(join(sessionsDir, "pre-session.jsonl"), lines([preEvent]));

    createOutputManager({ sessionsDir });

    // session-001 untouched
    const sessAfter = await readFile(
      join(sessionsDir, "session-001.jsonl"),
      "utf-8"
    );
    assert.equal(sessAfter, sessContent);

    // pre-session.jsonl rotated away
    const names = await readdir(sessionsDir);
    assert.ok(!names.includes("pre-session.jsonl"));

    // exactly 20 rotated archives
    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n)).sort();
    assert.equal(rotated.length, 20);

    // freshest rotated file is the today-stamp (lex-greater than 2026-01-25...)
    const freshest = rotated[rotated.length - 1];
    assert.ok(
      freshest > "pre-session-2026-01-25T00-00-00-000Z.jsonl",
      `freshest archive should be lex-greater than the seed range: ${freshest}`
    );
  } finally {
    await cleanup();
  }
});

test("output-manager gc: tolerates missing sessions dir without throwing", () => {
  const om = createOutputManager({
    sessionsDir: "/path/that/does/not/exist/compass-gc-test",
  });
  assert.deepEqual(om.getBuffer(), []);
});

function sessionLogName(n: number): string {
  return `session-${String(n).padStart(3, "0")}.jsonl`;
}

test("gc session logs: keeps the K most recent session logs (numeric N order)", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 1; i <= 250; i++) {
      await writeFile(
        join(sessionsDir, sessionLogName(i)),
        lines([ev("log", `s${i}`, i)])
      );
    }

    createOutputManager({ sessionsDir });

    const names = await readdir(sessionsDir);
    const sessions = names.filter((n) => /^session-\d+\.jsonl$/.test(n));
    assert.equal(sessions.length, 200);

    const ns = new Set(
      sessions.map((n) => {
        const m = n.match(/^session-(\d+)\.jsonl$/);
        return Number(m![1]);
      })
    );
    const expected = new Set<number>();
    for (let i = 51; i <= 250; i++) expected.add(i);
    assert.deepEqual(ns, expected);
  } finally {
    await cleanup();
  }
});

test("gc session logs: respects custom maxSessionLogs option", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 1; i <= 10; i++) {
      await writeFile(
        join(sessionsDir, sessionLogName(i)),
        lines([ev("log", `s${i}`, i)])
      );
    }

    createOutputManager({ sessionsDir, maxSessionLogs: 3 });

    const names = await readdir(sessionsDir);
    const sessions = names.filter((n) => /^session-\d+\.jsonl$/.test(n));
    assert.equal(sessions.length, 3);

    const ns = new Set(
      sessions.map((n) => {
        const m = n.match(/^session-(\d+)\.jsonl$/);
        return Number(m![1]);
      })
    );
    assert.deepEqual(ns, new Set([8, 9, 10]));
  } finally {
    await cleanup();
  }
});

test("gc session logs: no-op when at or below the cap", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 1; i <= 5; i++) {
      await writeFile(
        join(sessionsDir, sessionLogName(i)),
        lines([ev("log", `s${i}`, i)])
      );
    }

    createOutputManager({ sessionsDir });

    const names = await readdir(sessionsDir);
    const sessions = names.filter((n) => /^session-\d+\.jsonl$/.test(n));
    assert.equal(sessions.length, 5);
  } finally {
    await cleanup();
  }
});

test("gc session logs: floors maxSessionLogs at 1", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 1; i <= 5; i++) {
      await writeFile(
        join(sessionsDir, sessionLogName(i)),
        lines([ev("log", `s${i}`, i)])
      );
    }

    createOutputManager({ sessionsDir, maxSessionLogs: 0 });

    const names = await readdir(sessionsDir);
    const sessions = names.filter((n) => /^session-\d+\.jsonl$/.test(n));
    assert.equal(sessions.length, 1);

    const m = sessions[0].match(/^session-(\d+)\.jsonl$/);
    assert.ok(m);
    assert.equal(Number(m![1]), 5);
  } finally {
    await cleanup();
  }
});

test("gc session logs: sorts numerically not lexicographically (4-digit N)", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (const n of [998, 999, 1000, 1001, 1002, 1003]) {
      await writeFile(
        join(sessionsDir, sessionLogName(n)),
        lines([ev("log", `s${n}`, n)])
      );
    }

    createOutputManager({ sessionsDir, maxSessionLogs: 3 });

    const names = await readdir(sessionsDir);
    const sessions = names.filter((n) => /^session-\d+\.jsonl$/.test(n));
    assert.equal(sessions.length, 3);

    const ns = new Set(
      sessions.map((n) => {
        const m = n.match(/^session-(\d+)\.jsonl$/);
        return Number(m![1]);
      })
    );
    assert.deepEqual(ns, new Set([1001, 1002, 1003]));
  } finally {
    await cleanup();
  }
});

test("gc session logs: leaves pre-session archives and pre-session.jsonl alone", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    for (let i = 1; i <= 250; i++) {
      await writeFile(
        join(sessionsDir, sessionLogName(i)),
        lines([ev("log", `s${i}`, i)])
      );
    }

    // One rotated archive (seed)
    await writeFile(
      join(sessionsDir, "pre-session-2026-01-01T00-00-00-000Z.jsonl"),
      lines([ev("log", "old-pre", 1)])
    );

    // Active pre-session.jsonl with a valid event (gets rotated by ctor)
    await writeFile(
      join(sessionsDir, "pre-session.jsonl"),
      lines([ev("log", "active-pre", 99)])
    );

    createOutputManager({ sessionsDir });

    const names = await readdir(sessionsDir);

    const sessions = names.filter((n) => /^session-\d+\.jsonl$/.test(n));
    assert.equal(sessions.length, 200);

    const rotated = names.filter((n) => /^pre-session-.+\.jsonl$/.test(n));
    assert.equal(rotated.length, 2);

    assert.ok(!names.includes("pre-session.jsonl"));
  } finally {
    await cleanup();
  }
});

test("gc session logs: ignores files that don't match session-NNN.jsonl pattern", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    // Non-matching files
    await writeFile(
      join(sessionsDir, "session-abc.jsonl"),
      JSON.stringify(ev("log", "no", 1)) + "\n"
    );
    await writeFile(
      join(sessionsDir, "session-.jsonl"),
      JSON.stringify(ev("log", "no", 1)) + "\n"
    );
    await writeFile(join(sessionsDir, "notes.txt"), "garbage");

    // 251 valid logs (N=1..251)
    for (let i = 1; i <= 251; i++) {
      await writeFile(
        join(sessionsDir, sessionLogName(i)),
        lines([ev("log", `s${i}`, i)])
      );
    }

    createOutputManager({ sessionsDir });

    const names = await readdir(sessionsDir);

    // Non-matching files survive
    assert.ok(names.includes("session-abc.jsonl"));
    assert.ok(names.includes("session-.jsonl"));
    assert.ok(names.includes("notes.txt"));

    const sessions = names.filter((n) => /^session-\d+\.jsonl$/.test(n));
    assert.equal(sessions.length, 200);

    const ns = new Set(
      sessions.map((n) => {
        const m = n.match(/^session-(\d+)\.jsonl$/);
        return Number(m![1]);
      })
    );
    const expected = new Set<number>();
    for (let i = 52; i <= 251; i++) expected.add(i);
    assert.deepEqual(ns, expected);
  } finally {
    await cleanup();
  }
});
