/**
 * Bundles the editor into `dist/`, which Xcode copies into the app bundle.
 *
 * Everything is inlined and self-contained: the WKWebView loads from a file URL
 * with no network access, so there can be no CDN or remote import at runtime.
 */
import { cp, mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { build, context } from "esbuild";

const root = path.dirname(fileURLToPath(import.meta.url));
const src = path.join(root, "src");
const dist = path.join(root, "dist");
const watch = process.argv.includes("--watch");

const options = {
  entryPoints: [path.join(src, "main.js")],
  outfile: path.join(dist, "editor.js"),
  bundle: true,
  format: "esm",
  target: ["safari17"],
  sourcemap: watch,
  minify: !watch,
  legalComments: "none",
};

await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });
await cp(path.join(src, "index.html"), path.join(dist, "index.html"));
await cp(path.join(src, "editor.css"), path.join(dist, "editor.css"));

if (watch) {
  const ctx = await context(options);
  await ctx.watch();
  console.log("watching " + path.relative(process.cwd(), src));
} else {
  await build(options);
  console.log(path.relative(process.cwd(), options.outfile));
}
