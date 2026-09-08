/** Word counting. The real module is imported, since it has no CodeMirror dependency. */
import assert from "node:assert/strict";
import test from "node:test";

import { countCharacters, countWords, documentStats } from "../src/wordcount.js";

test("counts plain English words", () => {
  assert.equal(countWords("the source is the truth"), 5);
});

test("collapses irregular whitespace", () => {
  assert.equal(countWords("  one   two\n\nthree\t four "), 4);
});

test("counts CJK per character, as Chinese editors do", () => {
  // No spaces between words, so whitespace splitting would say 1.
  assert.equal(countWords("源码是唯一的真相"), 8);
});

test("counts a mixed sentence without double counting", () => {
  // 3 Han characters + 2 English words.
  assert.equal(countWords("使用 CodeMirror 编辑"), 5);
});

test("excludes fenced code, which is not prose", () => {
  const text = "hello world\n\n```js\nconst a = 1; const b = 2;\n```\n\nagain";
  assert.equal(countWords(text), 3);
});

test("excludes inline code", () => {
  // "call" and "now"; the code span counts for nothing.
  assert.equal(countWords("call `someLongFunctionName()` now"), 2);
});

test("ignores punctuation on its own", () => {
  assert.equal(countWords("hi --- ... hi"), 2);
});

test("an empty document counts zero, not one", () => {
  assert.equal(countWords(""), 0);
  assert.equal(countWords("   \n  "), 0);
});

test("counts characters by what a reader sees", () => {
  // Two UTF-16 code units, one character.
  assert.equal(countCharacters("🙂"), 1);
  assert.equal(countCharacters("abc"), 3);
});

test("reports words, characters and lines together", () => {
  const stats = documentStats("one two\nthree");
  assert.deepEqual(stats, { words: 3, characters: 13, lines: 2 });
});
