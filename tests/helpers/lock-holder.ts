import { acquireWorkspaceLock } from "../../src/state/lock.ts";

async function main(): Promise<void> {
  const dir = process.argv[2];
  if (!dir) {
    console.error("usage: lock-holder.ts <workspace-dir>");
    process.exit(2);
  }
  const result = await acquireWorkspaceLock(dir);
  if (!result.ok) {
    console.error(`lock-holder: failed to acquire (existing pid=${result.pid})`);
    process.exit(3);
  }
  process.stdout.write(`ready pid=${process.pid}\n`);

  // Wait for stdin to close (parent signals release by ending stdin).
  await new Promise<void>((resolve) => {
    process.stdin.on("end", () => resolve());
    process.stdin.resume();
  });

  await result.lock.release();
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
