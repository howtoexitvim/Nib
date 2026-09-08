/**
 * Markdown formatting commands.
 *
 * The string transforms are pure and exported on their own, because that is
 * where the behaviour worth testing lives: what happens to a selection that
 * already has the markers, or that has trailing spaces, or none at all.
 */

/** Marker characters, by command name. */
const MARKERS = { bold: "**", italic: "*", code: "`" };

/**
 * Wraps or unwraps a selection.
 *
 * Toggling matters: selecting bold text and pressing Cmd+B again should
 * remove the bold, not produce ****text****.
 */
export function toggleWrap(text, marker) {
  const value = text ?? "";
  // Split off surrounding whitespace first. Select All catches the trailing
  // newline, and both decisions below have to be made about the text itself:
  // markers placed outside the newline land on their own line, and an
  // already-wrapped selection would not be recognised as one.
  const [, lead, body, trail] = /^(\s*)([\s\S]*?)(\s*)$/.exec(value);
  if (!body) return marker + value + marker;

  if (
    body.startsWith(marker) &&
    body.endsWith(marker) &&
    body.length >= marker.length * 2
  ) {
    return lead + body.slice(marker.length, body.length - marker.length) + trail;
  }
  return lead + marker + body + marker + trail;
}

/**
 * Sets a line's heading level; 0 clears it.
 *
 * Any existing heading is replaced rather than added to, so pressing Cmd+2 on
 * an H1 gives an H2 and not `## # Title`.
 */
export function setHeading(line, level) {
  const body = (line ?? "").replace(/^\s*#{1,6}\s+/, "").replace(/^\s+/, "");
  if (level <= 0) return body;
  // A blank line stays blank. Selecting a paragraph usually catches the empty
  // line after it, and turning that into a bare "##" is never what was meant.
  if (!body) return body;
  return `${"#".repeat(Math.min(level, 6))} ${body}`;
}

/**
 * A link, using the selection as the text.
 *
 * Surrounding whitespace stays outside the brackets, for the same reason the
 * wrap markers do: Select All catches the trailing newline, and a link whose
 * text ends in one is broken.
 */
export function makeLink(text, url = "") {
  const [, lead, body, trail] = /^(\s*)([\s\S]*?)(\s*)$/.exec(text ?? "");
  return `${lead}[${body}](${url})${trail}`;
}

/** Applies a wrapping command to every selected range. */
function wrapCommand(marker) {
  return (view) => {
    view.dispatch(
      view.state.changeByRange((range) => {
        const selected = view.state.sliceDoc(range.from, range.to);
        const replacement = toggleWrap(selected, marker);
        return {
          changes: { from: range.from, to: range.to, insert: replacement },
          // Put the cursor between the markers when nothing was selected, so
          // typing continues inside the formatting.
          range: view.state.selection.main.empty
            ? { anchor: range.from + marker.length }
            : { anchor: range.from, head: range.from + replacement.length },
        };
      })
    );
  };
}

export function applyHeading(view, level) {
  const changes = [];
  const { from, to } = view.state.selection.main;
  const first = view.state.doc.lineAt(from).number;
  const last = view.state.doc.lineAt(to).number;

  for (let number = first; number <= last; number += 1) {
    const line = view.state.doc.line(number);
    changes.push({ from: line.from, to: line.to, insert: setHeading(line.text, level) });
  }
  view.dispatch({ changes });
}

export function applyLink(view) {
  const { from, to } = view.state.selection.main;
  const selected = view.state.sliceDoc(from, to);
  const replacement = makeLink(selected);
  // Land the cursor inside the parentheses, ready for the URL -- which is
  // before the closing paren and any whitespace that was kept outside.
  const trailing = /\s*$/.exec(replacement)[0].length;
  view.dispatch({
    changes: { from, to, insert: replacement },
    selection: { anchor: from + replacement.length - trailing - 1 },
  });
}

export const formatCommands = {
  bold: wrapCommand(MARKERS.bold),
  italic: wrapCommand(MARKERS.italic),
  code: wrapCommand(MARKERS.code),
  link: applyLink,
  heading: (view, argument) => applyHeading(view, Number(argument) || 0),
};
