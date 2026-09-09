/**
 * Commands the menu bar can run.
 *
 * Registered by name in one table, so the Swift side only needs a single
 * `command(name, argument)` entry point rather than a bridge function per
 * menu item. The bodies arrive with their features; this is the table and the
 * contract.
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

/** Adds a command, or replaces one, by name. */
export function register(name, run) {
  commands[name] = run;
}
