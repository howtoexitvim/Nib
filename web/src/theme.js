/**
 * Applying appearance settings.
 *
 * Everything is a CSS custom property, which both the CodeMirror theme and
 * the preview stylesheet already read -- so one place sets the look of both
 * modes, with no CodeMirror reconfiguration involved.
 */

/** Maps the theme choice onto the attribute the stylesheet keys off. */
export function applyAppearance(settings = {}) {
  const root = document.documentElement;

  if (settings.theme && settings.theme !== "system") {
    root.setAttribute("data-theme", settings.theme);
  } else {
    // Absent means "follow the system", which is what prefers-color-scheme
    // already does on its own.
    root.removeAttribute("data-theme");
  }

  for (const [name, value] of Object.entries({
    "--nib-font-family": settings.fontFamily,
    "--nib-font-size": settings.fontSize,
    "--nib-measure": settings.measure,
  })) {
    if (value) root.style.setProperty(name, value);
  }
}
