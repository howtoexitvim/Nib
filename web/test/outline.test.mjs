/** Outline parsing. */
import assert from "node:assert/strict";
import test from "node:test";

import { offsetOfLine, parseOutline } from "../src/outline.js";

test("reads headings with their levels", () => {
  const outline = parseOutline("# One\n\n## Two\n\n### Three");
  assert.deepEqual(outline, [
    { level: 1, text: "One", line: 0 },
    { level: 2, text: "Two", line: 2 },
    { level: 3, text: "Three", line: 4 },
  ]);
});

test("ignores headings inside a fenced block", () => {
  // A shell comment is not a section of the document.
  const outline = parseOutline("# Real\n\n```sh\n# not a heading\n```\n\n## Also real");
  assert.deepEqual(outline.map((h) => h.text), ["Real", "Also real"]);
});

test("handles a tilde fence too", () => {
  const outline = parseOutline("~~~\n# hidden\n~~~\n# shown");
  assert.deepEqual(outline.map((h) => h.text), ["shown"]);
});

test("strips closing hashes", () => {
  assert.equal(parseOutline("## Title ##")[0].text, "Title");
});

test("requires a space, so a hashtag is not a heading", () => {
  assert.deepEqual(parseOutline("#tag is not a heading"), []);
});

test("ignores a heading with no text", () => {
  assert.deepEqual(parseOutline("#\n##   "), []);
});

test("stops at six levels", () => {
  assert.equal(parseOutline("###### Six")[0].level, 6);
  assert.deepEqual(parseOutline("####### Seven"), []);
});

test("finds the character offset of a line", () => {
  const text = "# One\nbody\n## Two";
  assert.equal(offsetOfLine(text, 0), 0);
  assert.equal(offsetOfLine(text, 1), 6);
  assert.equal(offsetOfLine(text, 2), 11);
  assert.equal(text.slice(offsetOfLine(text, 2)), "## Two");
});

test("an empty document has no outline", () => {
  assert.deepEqual(parseOutline(""), []);
});
