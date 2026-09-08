/** Markdown formatting transforms. */
import assert from "node:assert/strict";
import test from "node:test";

import { makeLink, setHeading, toggleWrap } from "../src/format.js";

test("wraps a selection", () => {
  assert.equal(toggleWrap("text", "**"), "**text**");
  assert.equal(toggleWrap("text", "*"), "*text*");
  assert.equal(toggleWrap("text", "`"), "`text`");
});

test("unwraps text that is already wrapped", () => {
  // Otherwise pressing Cmd+B twice gives ****text****.
  assert.equal(toggleWrap("**text**", "**"), "text");
});

test("unwraps even when the selection carries a trailing newline", () => {
  // Select All always does, so this is the common case, not the edge one.
  assert.equal(toggleWrap("**text**\n", "**"), "text\n");
});

test("wraps an empty selection, so typing continues inside", () => {
  assert.equal(toggleWrap("", "**"), "****");
});

test("keeps the markers tight against the text", () => {
  // Select All catches the trailing newline; a marker after it would land on
  // its own line and render as literal asterisks.
  assert.equal(toggleWrap("text\n", "**"), "**text**\n");
  assert.equal(toggleWrap("  text  ", "*"), "  *text*  ");
});

test("does not mistake a single marker pair for a wrap", () => {
  // "*" is not italic text; it is one character that happens to be a marker.
  assert.equal(toggleWrap("*", "*"), "***");
});

test("sets a heading level", () => {
  assert.equal(setHeading("Title", 1), "# Title");
  assert.equal(setHeading("Title", 3), "### Title");
});

test("replaces an existing heading rather than stacking", () => {
  assert.equal(setHeading("# Title", 2), "## Title");
  assert.equal(setHeading("###### Title", 1), "# Title");
});

test("clears a heading at level 0", () => {
  assert.equal(setHeading("## Title", 0), "Title");
  assert.equal(setHeading("Title", 0), "Title");
});

test("leaves a blank line blank", () => {
  // Selecting a paragraph usually catches the empty line after it; turning
  // that into a bare "##" is never what was meant.
  assert.equal(setHeading("", 2), "");
  assert.equal(setHeading("   ", 2), "");
});

test("stops at six, the deepest Markdown heading", () => {
  assert.equal(setHeading("Title", 9), "###### Title");
});

test("does not treat a hashtag as a heading to replace", () => {
  // No space after the #, so it is not a heading.
  assert.equal(setHeading("#tag stays", 1), "# #tag stays");
});

test("makes a link with the cursor destination empty", () => {
  assert.equal(makeLink("Nib"), "[Nib]()");
  assert.equal(makeLink(""), "[]()");
});

test("keeps a trailing newline outside the link text", () => {
  // A link whose text ends in a newline is broken; Select All always
  // produces one.
  assert.equal(makeLink("Nib\n"), "[Nib]()\n");
});
