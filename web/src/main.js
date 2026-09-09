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

import { makeState } from "./state.js";
import { renderMarkdown } from "./preview.js";
import { documentStats } from "./wordcount.js";
import { activeHeading, offsetOfLine, parseOutline } from "./outline.js";
import { notifyOutline } from "./bridge.js";
import { installHostAPI, notifyDirty, notifyMode } from "./bridge.js";
import { commands } from "./commands.js";
import { applyAppearance, setThemeListener } from "./theme.js";
import { editorThemeFor, themeCompartment } from "./state.js";

const root = document.getElementById("root");
const previewEl = document.getElementById("preview");
const statsEl = document.getElementById("stats");

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
  if (update.docChanged) {
    notifyDirty(update.state.doc.toString() !== savedDoc);
    scheduleStats();
  } else if (update.selectionSet) {
    // Moving the cursor moves the outline highlight, but nothing else needs
    // recomputing -- counting words on every arrow key would be wasteful.
    scheduleActive();
  }
});

/** Pushes just the active-heading index, on cursor movement. */
let activeTimer = 0;
function scheduleActive() {
  clearTimeout(activeTimer);
  activeTimer = setTimeout(() => {
    const headings = parseOutline(view.state.doc.toString());
    notifyOutline(headings, activeHeading(headings, view.state.doc.lineAt(
      Math.min(view.state.selection.main.head, view.state.doc.length)
    ).number - 1));
  }, 150);
}

/**
 * Counting scans the whole document, so it runs after typing stops rather
 * than on every keystroke -- at 100k words the difference is visible.
 */
let statsTimer = 0;
function scheduleStats() {
  clearTimeout(statsTimer);
  statsTimer = setTimeout(updateStats, 200);
}

function updateStats() {
  const text = view.state.doc.toString();
  const { words, characters } = documentStats(text);
  statsEl.textContent = `${words.toLocaleString()} words · ${characters.toLocaleString()} characters`;
  // The sidebar's outline is native, so the structure is pushed to Swift
  // rather than rendered here.
  const headings = parseOutline(text);
  notifyOutline(headings, activeHeading(headings, view.state.doc.lineAt(
    Math.min(view.state.selection.main.head, view.state.doc.length)
  ).number - 1));
}

const view = new EditorView({
  parent: root,
  state: makeState("", undefined, [dirtyListener]),
});

function renderPreview() {
  // Wrapped so the pane itself scrolls and the text column stays centred --
  // otherwise the scrollbar sits inside the column rather than at the window
  // edge.
  previewEl.innerHTML =
    `<div class="preview-body">${renderMarkdown(view.state.doc.toString())}</div>`;
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
    updateStats();
    notifyDirty(false);
    if (mode === "source") view.focus();
  },
  getDoc: () => view.state.doc.toString(),
  /** Called after the host writes to disk, so the dirty flag matches reality. */
  markSaved() {
    savedDoc = view.state.doc.toString();
    notifyDirty(false);
  },
  /**
   * Runs a command sent by a menu item.
   *
   * One entry point rather than one host function per command, so adding a
   * menu item does not mean adding a bridge function too. Commands that need
   * a cursor are refused in preview, which has none.
   */
  command(name, argument) {
    // Find works from either mode: it locates text rather than editing it, so
    // it switches to source and opens the panel there. Everything else needs a
    // cursor, which the preview does not have.
    if (mode !== "source") {
      if (name !== "find") return;
      setMode("source");
    }
    const run = commands[name];
    if (!run) {
      console.warn("[nib] unknown command: " + name);
      return;
    }
    run(view, argument);
    view.focus();
  },
  /** Puts the cursor on a heading the outline was clicked on. */
  /**
   * Reveals a line, optionally selecting the text that was searched for.
   *
   * Switches to source first when a match is given: the preview is a read-only
   * projection with no cursor, so there is nothing there to select or land on.
   * Jumping there from a search result would show the right page and no
   * indication of what matched.
   */
  scrollToLine(line, match) {
    if (match && mode !== "source") setMode("source");

    const text = view.state.doc.toString();
    const lineStart = offsetOfLine(text, line);
    let from = lineStart;
    let to = lineStart;

    if (match) {
      // Find the match within the line, so the selection lands on the words
      // rather than on the start of the line.
      const lineText = text.slice(lineStart, text.indexOf("\n", lineStart) + 1 || undefined);
      const at = lineText.toLowerCase().indexOf(match.toLowerCase());
      if (at >= 0) {
        from = lineStart + at;
        to = from + match.length;
      }
    }

    view.dispatch({
      selection: { anchor: from, head: to },
      effects: EditorView.scrollIntoView(from, { y: "center" }),
    });
    if (mode === "source") view.focus();
  },
  applyAppearance,
  setMode,
  toggleMode,
  getMode: () => mode,
  focus: () => (mode === "source" ? view.focus() : previewEl.focus()),
});

// CodeMirror's baseTheme is chosen when the theme extension is built, so a
// light/dark switch has to reconfigure it -- CSS variables cannot reach it.
setThemeListener((dark) => {
  view.dispatch({ effects: themeCompartment.reconfigure(editorThemeFor(dark)) });
});

setMode("source");
updateStats();
