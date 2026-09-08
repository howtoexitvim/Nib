/**
 * Editor entry point.
 *
 * Two modes, and only two: a CodeMirror source editor, and a read-only rendered
 * preview. The source buffer is the single source of truth -- the preview is a
 * projection of it and is never edited, which is what keeps ghost text sound
 * (it has a real character offset to anchor to) and avoids the source/rendered
 * mapping problem that makes WYSIWYG Markdown editors so hard.
 */
import { EditorView } from "@codemirror/view";
import { marked } from "marked";

import { makeState } from "./state.js";
import { installHostAPI, notifyDirty, notifyMode } from "./bridge.js";

const root = document.getElementById("root");
const previewEl = document.getElementById("preview");

let savedDoc = "";
let mode = "source";
/** Path of the open file; "" for an untitled buffer. Keys the position memory. */
let currentPath = "";

/**
 * Cursor and scroll per file, so switching away and back lands where you left.
 * In memory only: persisting it would need invalidating on every rename.
 */
const positions = new Map();

/** Fires on every edit so the host can track the dirty state. */
const dirtyListener = EditorView.updateListener.of((update) => {
  if (update.docChanged) notifyDirty(update.state.doc.toString() !== savedDoc);
});

const view = new EditorView({
  parent: root,
  state: makeState("", undefined, [dirtyListener]),
});

marked.setOptions({ gfm: true, breaks: false });

function renderPreview() {
  previewEl.innerHTML = marked.parse(view.state.doc.toString());
}

/** Remembers where the cursor and scroll were in the file being left. */
function rememberPosition() {
  if (!currentPath) return;
  const { anchor, head } = view.state.selection.main;
  positions.set(currentPath, {
    anchor,
    head,
    scrollTop: view.scrollDOM.scrollTop,
  });
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
  /**
   * Replaces the buffer with another file's contents.
   *
   * Builds a fresh state rather than dispatching a change: a transaction would
   * preserve the undo history across the switch, so one undo would pull the
   * previous file's text into this buffer and the next save would write it to
   * disk. Losing cross-file undo is the correct trade.
   */
  setDoc(text, path = "") {
    rememberPosition();
    savedDoc = text ?? "";
    currentPath = path ?? "";
    view.setState(makeState(savedDoc, positions.get(currentPath), [dirtyListener]));

    const remembered = positions.get(currentPath);
    if (remembered?.scrollTop) view.scrollDOM.scrollTop = remembered.scrollTop;
    if (mode === "preview") renderPreview();
    notifyDirty(false);
    if (mode === "source") view.focus();
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
