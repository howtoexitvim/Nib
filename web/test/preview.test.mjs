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

test("does not double-encode a link Nib itself wrote", () => {
  // ImageStore percent-encodes when it writes the markdown, because a space or
  // a paren ends a link early. Encoding again turned %20 into %2520 and the
  // image was never found -- every pasted image whose document name had a
  // space or CJK in it rendered broken.
  const written = "1.%20%E4%B8%A4%E8%A1%8C.assets/image-1.png";
  assert.equal(
    resolveImageSrc(written),
    "nib-asset://asset/1.%20%E4%B8%A4%E8%A1%8C.assets/image-1.png"
  );
});

test("still encodes a path typed by hand", () => {
  assert.equal(
    resolveImageSrc("my notes.assets/a b.png"),
    "nib-asset://asset/my%20notes.assets/a%20b.png"
  );
  assert.equal(
    resolveImageSrc("笔记.assets/图片.png"),
    "nib-asset://asset/%E7%AC%94%E8%AE%B0.assets/%E5%9B%BE%E7%89%87.png"
  );
});

test("leaves a literal percent in a filename alone", () => {
  // "100%25" is an encoded "100%"; decoding first and re-encoding would be
  // lossy for a filename that genuinely contains a percent sign.
  assert.equal(
    resolveImageSrc("100%25.assets/x.png"),
    "nib-asset://asset/100%25.assets/x.png"
  );
});

test("resolving twice is still stable", () => {
  const once = resolveImageSrc("my notes.assets/a b.png");
  assert.equal(resolveImageSrc(once), once);
});
