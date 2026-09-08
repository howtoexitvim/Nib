/**
 * Builds the editor's EditorState.
 *
 * This is a factory rather than a one-off array because switching files must
 * create a *fresh* state: replacing the document with a transaction would keep
 * CodeMirror's undo history, so undo after a switch would pull the previous
 * file's text into the current buffer -- and the next save would write it to
 * disk. Cross-file undo is not offered, because without a document model it is
 * a corruption vector.
 */
import { EditorState } from "@codemirror/state";
import { EditorView, drawSelection, highlightActiveLine, keymap, rectangularSelection } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { markdown, markdownKeymap } from "@codemirror/lang-markdown";
import { highlightSelectionMatches, search, searchKeymap } from "@codemirror/search";
import { tags } from "@lezer/highlight";

import { ghostWriting } from "./ghost.js";
import { imagePaste } from "./paste.js";
import { requestCompletion } from "./bridge.js";

/**
 * Markdown syntax highlighting tuned for prose rather than code: structure is
 * distinguished by weight and subtle colour, not the rainbow a code theme uses.
 */
const proseHighlight = HighlightStyle.define([
  { tag: tags.heading1, fontWeight: "600", fontSize: "1.5em" },
  { tag: tags.heading2, fontWeight: "600", fontSize: "1.3em" },
  { tag: tags.heading3, fontWeight: "600", fontSize: "1.15em" },
  { tag: [tags.heading4, tags.heading5, tags.heading6], fontWeight: "600" },
  { tag: tags.strong, fontWeight: "600" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.link, color: "var(--nib-accent)", textDecoration: "underline" },
  { tag: tags.url, color: "var(--nib-faint)" },
  { tag: [tags.monospace], fontFamily: "var(--nib-mono)", color: "var(--nib-accent)" },
  { tag: tags.quote, color: "var(--nib-muted)", fontStyle: "italic" },
  { tag: [tags.processingInstruction, tags.meta], color: "var(--nib-faint)" },
  { tag: tags.list, color: "var(--nib-accent)" },
]);

const editorTheme = EditorView.theme({
  "&": {
    height: "100%",
    fontSize: "var(--nib-font-size)",
    backgroundColor: "var(--nib-bg)",
    color: "var(--nib-fg)",
  },
  ".cm-scroller": {
    fontFamily: "var(--nib-font-family)",
    lineHeight: "1.7",
    padding: "48px 0 45vh",
    overflowY: "auto",
  },
  // A measure-limited, centred column: long lines are a readability problem in
  // prose, and this is a writing app.
  ".cm-content": {
    maxWidth: "var(--nib-measure)",
    margin: "0 auto",
    padding: "0 24px",
    caretColor: "var(--nib-fg)",
  },
  "&.cm-focused": { outline: "none" },
  ".cm-line": { padding: "0" },
  ".cm-activeLine": { backgroundColor: "transparent" },
  ".cm-cursor": { borderLeftWidth: "2px", borderLeftColor: "var(--nib-fg)" },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground, ::selection": {
    backgroundColor: "var(--nib-selection)",
  },
  ".nib-ghost": { color: "var(--nib-faint)", fontStyle: "italic" },
});

/**
 * @param {string} doc initial text
 * @param {{anchor: number, head: number}} [selection] restored cursor, clamped
 *   to the document because a remembered position can outlive an external edit
 * @param {Array} [extra] extensions the caller adds, e.g. the dirty listener
 */
export function makeState(doc, selection, extra = []) {
  const max = doc.length;
  const anchor = Math.min(selection?.anchor ?? 0, max);
  const head = Math.min(selection?.head ?? anchor, max);

  return EditorState.create({
    doc,
    selection: { anchor, head },
    extensions: [
      history(),
      drawSelection(),
      rectangularSelection(),
      highlightActiveLine(),
      EditorView.lineWrapping,
      markdown(),
      syntaxHighlighting(proseHighlight),
      editorTheme,
      ghostWriting(requestCompletion),
      imagePaste(),
      // The panel is CodeMirror's own, styled through the same CSS variables
      // as the rest of the editor. Top placement matches every other macOS
      // find bar.
      search({ top: true }),
      highlightSelectionMatches(),
      // Cmd+/ belongs to the View menu. defaultKeymap binds it to toggleComment,
      // which would both comment out the line and fight the menu for the chord.
      // Search bindings before the defaults, so Enter and Escape belong to the
      // find panel while it is open.
      keymap.of(searchKeymap),
      // Enter continues a list or blockquote, Backspace removes the marker --
      // the behaviour every Markdown editor has and typing without feels
      // broken. Ahead of defaultKeymap, which binds a plain newline to Enter.
      keymap.of(markdownKeymap),
      keymap.of(
        [...defaultKeymap, ...historyKeymap].filter((binding) => binding.key !== "Mod-/"),
      ),
      ...extra,
    ],
  });
}
