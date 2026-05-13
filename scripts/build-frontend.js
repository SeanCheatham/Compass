import * as esbuild from "esbuild";
import { readFile, writeFile, mkdir } from "fs/promises";
import { join, dirname, extname } from "path";
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

  // Read CSS and inline local assets so the shipped frontend remains a single
  // tokenized HTML document.
  const cssContent = await inlineCssAssets(
    await readFile(join(srcDir, "styles.css"), "utf-8"),
    srcDir
  );

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

async function inlineCssAssets(css, baseDir) {
  const assetUrlPattern = /url\((["']?)(\.?\/?assets\/[^"')]+)\1\)/g;
  const replacements = new Map();

  for (const match of css.matchAll(assetUrlPattern)) {
    const rawUrl = match[2];
    if (replacements.has(rawUrl)) continue;

    const assetPath = join(baseDir, rawUrl.replace(/^\.\//, ""));
    const bytes = await readFile(assetPath);
    const mime = mimeTypeFor(assetPath);
    replacements.set(rawUrl, `data:${mime};base64,${bytes.toString("base64")}`);
  }

  let output = css;
  for (const [rawUrl, dataUri] of replacements) {
    output = output.replaceAll(rawUrl, dataUri);
  }
  return output;
}

function mimeTypeFor(path) {
  switch (extname(path).toLowerCase()) {
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".png":
      return "image/png";
    case ".webp":
      return "image/webp";
    case ".svg":
      return "image/svg+xml";
    default:
      return "application/octet-stream";
  }
}
