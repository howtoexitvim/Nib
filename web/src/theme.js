/**
 * Applying appearance settings.
 *
 * Everything is a CSS custom property, which both the CodeMirror theme and
 * the preview stylesheet already read -- so one place sets the look of both
 * modes, with no CodeMirror reconfiguration involved.
 */

/**
 * Called after the theme changes so CodeMirror can be reconfigured too.
 * Set by main.js, which owns the view.
 */
let onThemeChange = null;
export function setThemeListener(fn) {
  onThemeChange = fn;
}

/**
 * Follows the system when no explicit theme is set.
 *
 * Without this, choosing "System" and then changing the OS appearance would
 * repaint the CSS (the media query still applies) but leave CodeMirror on
 * whichever baseTheme it was built with.
 */
const systemQuery = window.matchMedia("(prefers-color-scheme: dark)");
systemQuery.addEventListener("change", () => {
  if (!document.documentElement.getAttribute("data-theme")) notifyTheme();
});

function notifyTheme() {
  const explicit = document.documentElement.getAttribute("data-theme");
  const dark = explicit ? explicit === "dark" : systemQuery.matches;
  if (onThemeChange) onThemeChange(dark);
}

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

  notifyTheme();
}
