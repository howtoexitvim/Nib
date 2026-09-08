/**
 * Trigger-strategy tests.
 *
 * The trigger rules decide whether ghost writing feels helpful or intrusive, so
 * they are tested directly. The rules live in ghost.js; this file re-declares
 * them and asserts the two stay in step (checked by the sync test below), which
 * avoids importing CodeMirror into a plain node run.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const TRIGGER_SUFFIXES = [
  "# ", ". ", ": ", ", ", "! ", "? ", "` ", "' ", "= ", "$ ", "> ", "\n",
  "。", "，", "：", "；", "！", "？", "、",
];

const TRIGGER_PATTERNS = [
  /[\t ]*(-|\*)[\t ]+$/,
  /[\t ]*[0-9A-Za-z]+\.[\t ]+$/,
];

function shouldTrigger(prefix) {
  return (
    TRIGGER_SUFFIXES.some((suffix) => prefix.endsWith(suffix)) ||
    TRIGGER_PATTERNS.some((pattern) => pattern.test(prefix))
  );
}

test("fires at the end of an English sentence", () => {
  assert.equal(shouldTrigger("The source is the truth. "), true);
});

test("fires after a comma or colon", () => {
  assert.equal(shouldTrigger("First, "), true);
  assert.equal(shouldTrigger("Note: "), true);
});

test("fires on a new line", () => {
  assert.equal(shouldTrigger("A paragraph.\n"), true);
});

test("fires after a heading marker", () => {
  assert.equal(shouldTrigger("# "), true);
  assert.equal(shouldTrigger("### "), true);
});

test("fires on a new list item, bulleted or numbered", () => {
  assert.equal(shouldTrigger("- "), true);
  assert.equal(shouldTrigger("  * "), true);
  assert.equal(shouldTrigger("1. "), true);
  assert.equal(shouldTrigger("   12. "), true);
});

test("fires after full-width CJK punctuation, which has no trailing space", () => {
  // Without these a Chinese document would almost never trigger, since CJK
  // writing does not put a space after punctuation.
  assert.equal(shouldTrigger("源码是唯一的真相。"), true);
  assert.equal(shouldTrigger("首先，"), true);
  assert.equal(shouldTrigger("注意："), true);
});

test("stays quiet mid-word", () => {
  // The whole point of trigger characters: not firing on every keystroke.
  assert.equal(shouldTrigger("The sourc"), false);
  assert.equal(shouldTrigger("源码是唯"), false);
});

test("stays quiet mid-sentence after a plain space", () => {
  assert.equal(shouldTrigger("The source is "), false);
});

test("does not treat a decimal point as a list item", () => {
  // "3.14" must not look like a numbered list; the pattern needs the space.
  assert.equal(shouldTrigger("pi is 3.14"), false);
});

test("the rules here match the ones shipped in ghost.js", () => {
  // Guards against this file drifting from the implementation it documents.
  const source = readFileSync(new URL("../src/ghost.js", import.meta.url), "utf8");
  for (const suffix of TRIGGER_SUFFIXES) {
    const literal = suffix === "\n" ? '"\\n"' : JSON.stringify(suffix);
    assert.ok(source.includes(literal), `ghost.js is missing trigger ${literal}`);
  }
  assert.ok(source.includes("DEBOUNCE_MS = 500"), "debounce changed");
  assert.ok(source.includes("MAX_PREFIX = 4000"), "prefix limit changed");
  assert.ok(source.includes("MAX_SUFFIX = 4000"), "suffix limit changed");
});
