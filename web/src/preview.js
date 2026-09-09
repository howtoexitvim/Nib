/**
 * Rendering the preview.
 *
 * The only real work here is images. A relative link like
 * `doc.assets/image-1.png` resolves against the *bundle* -- where the page
 * lives -- not against the document, so it would never be found. And the page
 * is granted read access to the bundle's web/ directory only, so even a
 * correct path would be refused.
 *
 * Both are solved by rewriting the src to a custom scheme that Swift serves.
 * A <base> tag would have been simpler, but it would also rewrite
 * ./editor.css and ./editor.js and break the app on load.
 */
import { marked } from "marked";

/** Links Swift resolves against the open document's folder. */
const ASSET_SCHEME = "nib-asset://asset/";

/** Schemes that already address something and must be left alone. */
const ABSOLUTE = /^(https?:|data:|nib-asset:|mailto:|file:)/i;

/**
 * Rewrites a relative image path to the custom scheme.
 *
 * Exported for its own test: this is pure string work, and it is the piece
 * most likely to be wrong.
 */
export function resolveImageSrc(src) {
  if (!src) return "";
  if (ABSOLUTE.test(src)) return src;
  // An absolute filesystem path is still a local file; hand it over as-is and
  // let Swift decide, rather than joining it onto the document folder.
  if (src.startsWith("/")) return `nib-asset://asset${src}`;
  // Encode only what is not already encoded. A Markdown link written by Nib is
  // already percent-encoded (ImageStore does it, because a space or a paren
  // ends a link early), so encoding again turned %20 into %2520 and the file
  // was never found -- which is why an image whose name had a space or CJK
  // showed as broken while a plain ASCII one worked.
  return ASSET_SCHEME + src.split("/").map(encodeSegment).join("/");
}

/**
 * Percent-encodes a path segment without double-encoding existing escapes.
 *
 * decodeURIComponent first would corrupt a literal "%" in a filename, so this
 * instead leaves valid %XX triplets alone and encodes everything else.
 */
function encodeSegment(segment) {
  return segment.replace(/%[0-9A-Fa-f]{2}|[^A-Za-z0-9\-._~!$&'()*+,;=:@]/g, (match) =>
    match.length === 3 && match[0] === "%" ? match : encodeURIComponent(match),
  );
}

const renderer = new marked.Renderer();
const renderImage = renderer.image.bind(renderer);
renderer.image = function image(token) {
  return renderImage({ ...token, href: resolveImageSrc(token.href) });
};

marked.setOptions({ gfm: true, breaks: false, renderer });

export function renderMarkdown(text) {
  return marked.parse(text);
}
