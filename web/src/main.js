/**
 * Editor entry point.
 *
 * Two modes, and only two: a CodeMirror source editor, and a read-only rendered
 * preview. The source buffer is the single source of truth -- the preview is a
 * projection of it and is never edited, which is what keeps ghost text sound
 * (it has a real character offset to anchor to) and avoids the source/rendered
 * mapping problem that makes WYSIWYG Markdown editors so hard.
 */
import { EditorState } from "@codemirror/state";
import { EditorView, drawSelection, highlightActiveLine, keymap, rectangularSelection } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { markdown } from "@codemirror/lang-markdown";
import { tags } from "@lezer/highlight";
import { marked } from "marked";

import { ghostWriting } from "./ghost.js";
import { installHostAPI, notifyDirty, notifyMode, requestCompletion } from "./bridge.js";

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
    fontFamily: "var(--nib-serif)",
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

const root = document.getElementById("root");
const previewEl = document.getElementById("preview");

let savedDoc = "";
let mode = "source";

const view = new EditorView({
  parent: root,
  state: EditorState.create({
    doc: "",
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
      // Cmd+/ belongs to the View menu. defaultKeymap binds it to toggleComment,
      // which would both comment out the line and fight the menu for the chord.
      keymap.of(
        [...defaultKeymap, ...historyKeymap].filter((binding) => binding.key !== "Mod-/"),
      ),
      EditorView.updateListener.of((update) => {
        if (update.docChanged) notifyDirty(view.state.doc.toString() !== savedDoc);
      }),
    ],
  }),
});

marked.setOptions({ gfm: true, breaks: false });

function renderPreview() {
  previewEl.innerHTML = marked.parse(view.state.doc.toString());
}

/**
 * Switches modes. The editor is detached from the tab order in preview so it
 * cannot receive input -- ghost text has no way to fire while rendered.
 */
function setMode(next) {
  mode = next;
  const isPreview = mode === "preview";
  root.hidden = isPreview;
  previewEl.hidden = !isPreview;
  if (isPreview) {
    renderPreview();
    previewEl.focus();
  } else {
    view.focus();
  }
  notifyMode(mode);
}

function toggleMode() {
  setMode(mode === "source" ? "preview" : "source");
}

// Cmd+/ is owned by the View menu, not bound here. Binding it in both places
// fired the toggle twice per press, which read as a phantom third mode: source
// -> preview -> source, but with CodeMirror's own Cmd+/ (toggle comment) also
// firing, so the document came back wrapped in <!-- -->.

installHostAPI({
  /** Replaces the buffer, e.g. when the host opens a file. */
  setDoc(text) {
    savedDoc = text ?? "";
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: savedDoc },
      selection: { anchor: 0 },
    });
    if (mode === "preview") renderPreview();
    notifyDirty(false);
  },
  getDoc: () => view.state.doc.toString(),
  /** Called after the host writes to disk, so the dirty flag matches reality. */
  markSaved() {
    savedDoc = view.state.doc.toString();
    notifyDirty(false);
  },
  setMode,
  toggleMode,
  getMode: () => mode,
  focus: () => (mode === "source" ? view.focus() : previewEl.focus()),
});

setMode("source");
