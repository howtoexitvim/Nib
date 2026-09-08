/**
 * The document's heading structure.
 *
 * Parsed from the text rather than from the syntax tree: the pure function is
 * testable on its own, and it is the same information either way. ATX headings
 * only (`# Title`), which is what Markdown files in practice use.
 */

/** A fence toggles whether following lines are code. */
const FENCE = /^\s{0,3}(```|~~~)/;
const HEADING = /^(#{1,6})\s+(.*?)\s*#*\s*$/;

/**
 * Returns `[{level, text, line}]` in document order.
 *
 * Headings inside a fenced block are skipped: a `# comment` in a shell snippet
 * is not a section of the document.
 */
export function parseOutline(text) {
  const headings = [];
  let inFence = false;

  (text ?? "").split("\n").forEach((line, index) => {
    if (FENCE.test(line)) {
      inFence = !inFence;
      return;
    }
    if (inFence) return;

    const match = HEADING.exec(line);
    if (!match) return;
    const title = match[2].trim();
    if (!title) return;

    headings.push({ level: match[1].length, text: title, line: index });
  });

  return headings;
}

/** Character offset of the start of a line, for scrolling to a heading. */
export function offsetOfLine(text, line) {
  const lines = (text ?? "").split("\n");
  let offset = 0;
  for (let i = 0; i < line && i < lines.length; i += 1) {
    offset += lines[i].length + 1; // +1 for the newline
  }
  return offset;
}
