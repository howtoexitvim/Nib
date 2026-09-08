/**
 * Commands the menu bar can run.
 *
 * Registered by name in one table, so the Swift side only needs a single
 * `command(name, argument)` entry point rather than a bridge function per
 * menu item. The bodies arrive with their features; this is the table and the
 * contract.
 */

import { openSearchPanel } from "@codemirror/search";

/** name -> (view, argument) => void */
export const commands = {
  find: (view) => openSearchPanel(view),
  // One panel serves both; it opens with the replace row already showing.
  replace: (view) => openSearchPanel(view),
};

/** Adds a command, or replaces one, by name. */
export function register(name, run) {
  commands[name] = run;
}
