import { cp, mkdir } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const srcDir = join(__dirname, "..", "src", "docs");
const distDir = join(__dirname, "..", "dist", "docs");

async function copyDocs() {
  await mkdir(distDir, { recursive: true });
  await cp(srcDir, distDir, { recursive: true });
}

copyDocs().catch((err) => {
  console.error("Docs copy failed:", err);
  process.exit(1);
});
