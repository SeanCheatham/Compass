import * as esbuild from "esbuild";
import { readFile, writeFile, mkdir } from "fs/promises";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const srcDir = join(__dirname, "..", "src", "web", "frontend");
const distDir = join(__dirname, "..", "dist", "web", "frontend");

async function build() {
  console.log("Building frontend...");

  // Ensure output directory exists
  await mkdir(distDir, { recursive: true });

  // Build TypeScript to JavaScript
  const result = await esbuild.build({
    entryPoints: [join(srcDir, "app.ts")],
    bundle: true,
    minify: true,
    format: "iife",
    target: ["es2020"],
    write: false,
  });

  const jsContent = result.outputFiles[0].text;

  // Read CSS
  const cssContent = await readFile(join(srcDir, "styles.css"), "utf-8");

  // Read HTML template
  let htmlContent = await readFile(join(srcDir, "index.html"), "utf-8");

  // Inline CSS - replace the link tag with a style tag
  htmlContent = htmlContent.replace(
    '<link rel="stylesheet" href="styles.css">',
    `<style>\n${cssContent}\n</style>`
  );

  // Inline JS - replace the script tag with inline script
  htmlContent = htmlContent.replace(
    '<script src="app.js"></script>',
    `<script>\n${jsContent}\n</script>`
  );

  // Write bundled HTML
  await writeFile(join(distDir, "index.html"), htmlContent);

  console.log("Frontend built successfully!");
}

build().catch((err) => {
  console.error("Build failed:", err);
  process.exit(1);
});
