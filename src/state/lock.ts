import { readFile, writeFile, unlink, mkdir } from "fs/promises";
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

  try {
    const raw = await readFile(pidfilePath, "utf-8");
    const existingPid = parseInt(raw.trim(), 10);
    if (Number.isFinite(existingPid) && existingPid > 0 && isAlive(existingPid)) {
      return { ok: false, pid: existingPid, pidfilePath };
    }
    // Stale pidfile — fall through and overwrite.
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") {
      throw err;
    }
  }

  await writeFile(pidfilePath, String(process.pid) + "\n", "utf-8");

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
