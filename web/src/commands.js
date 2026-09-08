/**
 * Commands the menu bar can run.
 *
 * Registered by name in one table, so the Swift side only needs a single
 * `command(name, argument)` entry point rather than a bridge function per
 * menu item. The bodies arrive with their features; this is the table and the
 * contract.
 */

/** name -> (view, argument) => void */
export const commands = {};

/** Adds a command, or replaces one, by name. */
export function register(name, run) {
  commands[name] = run;
}
