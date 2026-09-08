/**
 * Talks to the Swift host.
 *
 * The API key never reaches this context: completion requests are forwarded to
 * Swift, which holds the key in the Keychain and makes the network call. This
 * side only ever sees prose in and prose out.
 */

/** Pending host calls, keyed by request id. */
const pending = new Map();
let nextId = 1;

function post(channel, payload) {
  const handler = window.webkit?.messageHandlers?.[channel];
  if (!handler) return false;
  handler.postMessage(payload);
  return true;
}

/**
 * Asks the host to complete at the cursor.
 *
 * Resolves to "" when no host is attached, so the editor stays fully usable
 * when opened in a plain browser during development.
 */
export function requestCompletion({ prefix, suffix }) {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    const sent = post("completion", { id, prefix, suffix });
    if (!sent) {
      resolve("");
      return;
    }
    pending.set(id, { resolve, reject });
  });
}

/**
 * Asks the host to write a pasted image beside the document.
 *
 * Resolves to the Markdown to insert. Rejects when there is nowhere to write
 * -- an unsaved document has no folder to put an assets directory next to.
 */
export function requestImageSave(base64) {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    const sent = post("document", { event: "pasteImage", id, data: base64 });
    if (!sent) {
      reject(new Error("no host attached"));
      return;
    }
    pending.set(id, { resolve, reject });
  });
}

/** Called by Swift once a pasted image is written, or has failed to be. */
function deliverImage(id, markdown, error) {
  const entry = pending.get(id);
  if (!entry) return;
  pending.delete(id);
  if (error) entry.reject(new Error(error));
  else entry.resolve(markdown ?? "");
}

/** Called by Swift with the result of a completion request. */
function deliverCompletion(id, text, error) {
  const entry = pending.get(id);
  if (!entry) return;
  pending.delete(id);
  if (error) entry.reject(new Error(error));
  else entry.resolve(text ?? "");
}

/** Tells the host the document changed, so it can track the dirty state. */
export function notifyDirty(isDirty) {
  post("document", { event: "dirty", isDirty });
}

/** Tells the host which mode is showing, so the menu item can stay in sync. */
export function notifyMode(mode) {
  post("document", { event: "mode", mode });
}

/** Tells the host the document's heading structure, for the outline pane. */
export function notifyOutline(headings) {
  post("document", { event: "outline", headings });
}

/** Surface for Swift to call into. Kept to a minimum and documented here. */
export function installHostAPI(api) {
  window.nib = Object.assign(window.nib ?? {}, api, { deliverCompletion, deliverImage });
}
