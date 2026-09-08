/**
 * Counting words in Markdown.
 *
 * Pure string work with no CodeMirror import, so the real implementation is
 * what the tests exercise rather than a copy of its rules.
 *
 * CJK is counted per character, which is the convention every Chinese editor
 * uses: there are no spaces between words, so splitting on whitespace would
 * report a 2,000-character essay as a handful of "words".
 */

/** Han, Hiragana, Katakana, Hangul: scripts that do not space their words. */
const CJK = /[぀-ヿ㐀-䶿一-鿿豈-﫿가-힯]/gu;

/** Code is not prose, so it does not count towards a writing target. */
function stripCode(text) {
  return text
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/~~~[\s\S]*?~~~/g, " ")
    .replace(/`[^`\n]*`/g, " ");
}

export function countWords(text) {
  const prose = stripCode(text ?? "");

  const cjk = (prose.match(CJK) ?? []).length;
  // Remove the CJK already counted, so a mixed sentence is not counted twice.
  const rest = prose.replace(CJK, " ");
  const words = rest.split(/\s+/).filter((word) => /[\p{L}\p{N}]/u.test(word)).length;

  return cjk + words;
}

export function countCharacters(text) {
  // Spread rather than .length: an emoji is one character to a reader, but
  // two UTF-16 code units to .length.
  return [...(text ?? "")].length;
}

/** Everything the status bar shows, computed in one pass over the document. */
export function documentStats(text) {
  return {
    words: countWords(text),
    characters: countCharacters(text),
    lines: (text ?? "").split("\n").length,
  };
}
