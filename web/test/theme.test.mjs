/**
 * Theme token integrity.
 *
 * Nib has three theme states -- system-light, system-dark, and an explicit
 * choice -- served by three CSS blocks. A token defined in one but not the
 * others silently breaks whichever state it is missing from, and nothing else
 * in the test suite would catch it.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const css = readFileSync(new URL("../src/editor.css", import.meta.url), "utf8");

function tokensIn(block) {
  const found = {};
  for (const [, name, value] of block.matchAll(/(--nib-[a-z-]+):\s*([^;]+);/g)) {
    found[name] = value.trim();
  }
  return found;
}

const lightBlock = css.slice(css.indexOf(":root {"), css.indexOf("@media"));
const mediaBlock = css.match(/@media \(prefers-color-scheme: dark\)[\s\S]*?\n {2}\}\n\}/)[0];
const explicitBlock = css.match(/:root\[data-theme="dark"\] \{[\s\S]*?\n\}/)[0];

/** Set by the appearance settings at runtime, not by a palette block. */
const NON_PALETTE = new Set([
  "--nib-serif", "--nib-sans", "--nib-mono",
  "--nib-font-size", "--nib-measure", "--nib-font-family",
]);

const lightPalette = Object.fromEntries(
  Object.entries(tokensIn(lightBlock)).filter(([k]) => !NON_PALETTE.has(k))
);

test("the two dark blocks define exactly the same tokens", () => {
  const media = tokensIn(mediaBlock);
  const explicit = tokensIn(explicitBlock);
  assert.deepEqual(
    Object.keys(media).sort(),
    Object.keys(explicit).sort(),
    "a token in one dark block but not the other breaks that theme state"
  );
});

test("the two dark blocks give the same values", () => {
  // They apply under different conditions (system dark vs an explicit choice)
  // and cannot be merged, so drift between them is the failure mode.
  assert.deepEqual(tokensIn(mediaBlock), tokensIn(explicitBlock));
});

test("every light palette token is overridden in dark", () => {
  const dark = tokensIn(explicitBlock);
  for (const name of Object.keys(lightPalette)) {
    assert.ok(dark[name], `${name} has no dark value, so it stays light in dark mode`);
  }
});

test("no dark-only token exists", () => {
  // One that light never defines would be undefined in light mode.
  const dark = tokensIn(explicitBlock);
  for (const name of Object.keys(dark)) {
    assert.ok(lightPalette[name], `${name} is defined only in dark`);
  }
});

test("every token used in a rule is defined", () => {
  const used = new Set([...css.matchAll(/var\((--nib-[a-z-]+)/g)].map((m) => m[1]));
  const defined = new Set([...Object.keys(lightPalette), ...NON_PALETTE]);
  for (const name of used) {
    assert.ok(defined.has(name), `${name} is used but never defined`);
  }
});

test("no colour is hardcoded outside the palette blocks", () => {
  // A literal in a rule cannot follow the theme.
  const body = css.slice(css.indexOf(explicitBlock) + explicitBlock.length);
  const withoutComments = body.replace(/\/\*[\s\S]*?\*\//g, "");
  const literals = withoutComments.match(/#[0-9a-fA-F]{3,8}\b|\brgba?\(/g) || [];
  assert.deepEqual(literals, [], `hardcoded colours cannot follow the theme: ${literals}`);
});

test("the editor background matches macOS's document background", () => {
  // #1E1E1E is textBackgroundColor in dark mode. Matching it means the WebView
  // and the native window frame paint the same colour instead of meeting at a
  // visible seam.
  assert.equal(tokensIn(explicitBlock)["--nib-bg"], "#1e1e1e");
});
