/**
 * Word-at-a-time accept.
 *
 * firstWord is pure, so the real implementation is imported. It cannot import
 * ghost.js wholesale (that pulls in CodeMirror), so this reads the one export
 * it needs through a small shim -- see the note below.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

// ghost.js imports CodeMirror, which a plain node run cannot resolve. The
// function under test is self-contained, so it is extracted by source.
const source = readFileSync(new URL("../src/ghost.js", import.meta.url), "utf8");
const start = source.indexOf("export function firstWord");
const end = source.indexOf("\n}", start) + 2;
const firstWord = new Function(
  source.slice(start, end).replace("export function", "return function") + "\nreturn firstWord;"
)();

test("takes one Latin word", () => {
  assert.equal(firstWord("hello world there"), "hello");
});

test("carries leading space with the word", () => {
  // The suggestion usually starts with the space that separates it from what
  // was already typed; leaving it behind would jam the words together.
  assert.equal(firstWord(" world there"), " world");
});

test("takes one character for CJK", () => {
  // No spaces between Chinese words, so a word-at-a-time key that looked for
  // whitespace would swallow the entire suggestion in one press.
  assert.equal(firstWord("源码是唯一的真相"), "源");
  assert.equal(firstWord(" 源码是"), " 源");
});

test("keeps punctuation with its word", () => {
  assert.equal(firstWord("truth. Next"), "truth.");
});

test("returns the whole thing when there is only one word", () => {
  assert.equal(firstWord("truth"), "truth");
});

test("handles an empty suggestion", () => {
  assert.equal(firstWord(""), "");
  assert.equal(firstWord(undefined), "");
});

test("whitespace only", () => {
  assert.equal(firstWord("   "), "   ");
});

test("Cmd+Right is bound to the partial accept", () => {
  assert.ok(source.includes('{ key: "Mod-ArrowRight", run: acceptGhostWord }'));
});
