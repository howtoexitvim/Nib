/**
 * Commands the menu bar can run.
 *
 * One table keyed by name, so the Swift side needs a single
 * `command(name, argument)` entry point rather than a bridge function per
 * menu item.
 */

import { openSearchPanel } from "@codemirror/search";

import { formatCommands } from "./format.js";

/** name -> (view, argument) => void */
export const commands = {
  // CodeMirror's panel carries its own replace toggle, so there is one
  // command, not a separate "find" and "find and replace" that opened the
  // very same panel.
  find: (view) => openSearchPanel(view),
  ...formatCommands,
};
