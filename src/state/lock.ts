import { open, readFile, unlink, mkdir } from "fs/promises";
import { resolve } from "path";

/**
 * Pidfile-based lock for a workspace. Refuses to take the lock if the existing
 * pid is still alive — prevents two `compass` processes from clobbering the
 * same `.compass/` directory.
 */

export interface WorkspaceLock {
  release(): Promise<void>;
}

export interface AcquireLockResult {
  ok: true;
  lock: WorkspaceLock;
}

export interface AcquireLockFailure {
  ok: false;
  pid: number;
  pidfilePath: string;
}

export type AcquireLockResultOrFailure =
  | AcquireLockResult
  | AcquireLockFailure;

const MAX_ATTEMPTS = 5;

function isAlive(pid: number): boolean {
  try {
    // Signal 0: no signal sent, but errno on the result tells us if the pid exists.
    process.kill(pid, 0);
    return true;
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    // EPERM means the process exists but we can't signal it (still locked).
    return code === "EPERM";
  }
}

export async function acquireWorkspaceLock(
  workspacePath: string
): Promise<AcquireLockResultOrFailure> {
  const pidfilePath = resolve(workspacePath, "compass.pid");

  await mkdir(workspacePath, { recursive: true });

  let lastSeenPid: number | null = null;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    // Atomic create-or-fail. POSIX O_EXCL | O_CREAT.
    let handle: import("fs/promises").FileHandle;
    try {
      handle = await open(pidfilePath, "wx");
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "EEXIST") throw err;
      // Pidfile exists — decide if its owner is live.
      let raw: string;
      try {
        raw = await readFile(pidfilePath, "utf-8");
      } catch (readErr) {
        if ((readErr as NodeJS.ErrnoException).code === "ENOENT") {
          // Race: someone unlinked between our open(wx) EEXIST and our readFile. Retry.
          continue;
        }
        throw readErr;
      }
      const existingPid = parseInt(raw.trim(), 10);
      if (
        Number.isFinite(existingPid) &&
        existingPid > 0 &&
        isAlive(existingPid)
      ) {
        return { ok: false, pid: existingPid, pidfilePath };
      }
      lastSeenPid = Number.isFinite(existingPid) ? existingPid : 0;
      // Stale. Best-effort unlink, then retry the open.
      try {
        await unlink(pidfilePath);
      } catch (unlinkErr) {
        if ((unlinkErr as NodeJS.ErrnoException).code !== "ENOENT") {
          throw unlinkErr;
        }
      }
      continue;
    }

    // We hold the lock — write our pid and close the handle.
    try {
      await handle.writeFile(String(process.pid) + "\n", "utf-8");
    } finally {
      await handle.close();
    }

    return {
      ok: true,
      lock: {
        async release(): Promise<void> {
          try {
            const raw = await readFile(pidfilePath, "utf-8");
            if (parseInt(raw.trim(), 10) === process.pid) {
              await unlink(pidfilePath);
            }
          } catch {
            // ignore — best-effort cleanup
          }
        },
      },
    };
  }

  // Exhausted retries — pathological case. Surface the last-seen pid (or 0).
  return { ok: false, pid: lastSeenPid ?? 0, pidfilePath };
}
