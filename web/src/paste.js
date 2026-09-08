/**
 * Pasting an image.
 *
 * The bytes go to Swift, which owns the filesystem; this side only inserts a
 * placeholder and swaps it for the returned Markdown when the write lands. The
 * placeholder matters: writing is asynchronous, and leaving the cursor sitting
 * on nothing while a large screenshot is encoded feels broken.
 */
import { EditorView } from "@codemirror/view";

import { requestImageSave } from "./bridge.js";

/** Marks where an image will land. Unique per paste so concurrent ones cannot cross. */
function placeholderFor(id) {
  return `![uploading ${id}…]()`;
}

/** Replaces the placeholder wherever it now sits, since text may have moved. */
function replacePlaceholder(view, id, replacement) {
  const placeholder = placeholderFor(id);
  const text = view.state.doc.toString();
  const at = text.indexOf(placeholder);
  if (at < 0) return;
  view.dispatch({
    changes: { from: at, to: at + placeholder.length, insert: replacement },
    selection: { anchor: at + replacement.length },
  });
}

/** Reads a File as a base64 string, which is what crosses the bridge. */
function toBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error);
    reader.onload = () => {
      const result = reader.result ?? "";
      // Strip the `data:<type>;base64,` prefix; Swift wants the payload only.
      resolve(String(result).slice(String(result).indexOf(",") + 1));
    };
    reader.readAsDataURL(file);
  });
}

let nextId = 1;

export function imagePaste() {
  return EditorView.domEventHandlers({
    paste(event, view) {
      const items = Array.from(event.clipboardData?.items ?? []);
      const image = items.find((item) => item.type.startsWith("image/"));
      if (!image) return false;

      const file = image.getAsFile();
      if (!file) return false;

      event.preventDefault();
      const id = nextId++;
      view.dispatch(view.state.replaceSelection(placeholderFor(id)));

      toBase64(file)
        .then((base64) => requestImageSave(base64))
        .then((markdown) => replacePlaceholder(view, id, markdown))
        .catch((error) => {
          // Leaving the placeholder behind would be worse than removing it:
          // it looks like a broken image that never resolves.
          replacePlaceholder(view, id, "");
          console.error("[nib] pasting the image failed: " + error.message);
        });

      return true;
    },
  });
}
