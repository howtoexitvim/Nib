/**
 * Image-source rewriting.
 *
 * Imported directly rather than re-declared: this module has no CodeMirror
 * dependency, so the real implementation is what gets tested.
 */
import assert from "node:assert/strict";
import test from "node:test";

import { resolveImageSrc } from "../src/preview.js";

test("rewrites a relative path to the scheme Swift serves", () => {
  assert.equal(
    resolveImageSrc("doc.assets/image-1.png"),
    "nib-asset://asset/doc.assets/image-1.png"
  );
});

test("encodes spaces, which would otherwise not survive as a URL", () => {
  assert.equal(
    resolveImageSrc("my notes.assets/shot 1.png"),
    "nib-asset://asset/my%20notes.assets/shot%201.png"
  );
});

test("does not encode the separators themselves", () => {
  // encodeURIComponent on the whole path would turn / into %2F and flatten it.
  assert.ok(resolveImageSrc("a/b/c.png").endsWith("/a/b/c.png"));
});

test("leaves remote and inline images alone", () => {
  for (const src of [
    "https://example.com/a.png",
    "http://example.com/a.png",
    "data:image/png;base64,AAAA",
  ]) {
    assert.equal(resolveImageSrc(src), src);
  }
});

test("does not rewrite what it already rewrote", () => {
  // Rendering happens on every keystroke in preview; a second pass must not
  // stack another prefix on.
  const once = resolveImageSrc("a.png");
  assert.equal(resolveImageSrc(once), once);
});

test("handles an empty src without producing a bare scheme", () => {
  assert.equal(resolveImageSrc(""), "");
  assert.equal(resolveImageSrc(undefined), "");
});
