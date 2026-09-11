<div align="center">

# Nib

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Markdown%20Editor-2563eb)
![Size](https://img.shields.io/badge/size-1.4MB-059669)

</div>

Nib is a minimal Markdown editor for macOS: a native Swift shell around a single WKWebView running CodeMirror 6.

It has **ghost writing**. At semantic boundaries — the end of a sentence, a new line, a new list item — your own LLM proposes a grey continuation. Tab accepts, Esc dismisses. You configure the provider; nothing is built in.

The API key lives in the Keychain and requests are issued from Swift, so the key never enters the JavaScript context.

## Install

Download the zip from the [releases page](https://github.com/howtoexitvim/Nib/releases), unzip it, and drag `Nib.app` into `/Applications`. The build is ad-hoc signed and not notarized, so clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Nib.app
```

Apple silicon (arm64) only. Latest release is **v0.1.0**.

Or build from source — it only needs a Swift toolchain and Node.

## Build

```bash
make        # build the web bundle and build/Nib.app
make run    # build and launch
make test   # Swift tests + JS tests
make clean
```

There is no Xcode project. `swift build` produces the binary and the Makefile assembles the `.app` by hand, so the whole thing is reproducible from the command line.

The result is about **1.4MB** (Typora is 46MB; Electron apps are typically 150-250MB).

## Two modes

Source mode is CodeMirror. Preview mode is a read-only render. **The source is the only truth; the preview is a projection.** `Cmd+/` toggles between them — the shortcut is bound on the window, so it works in both.

The preview is not editable and handles no input, so ghost text has **no code path** to fire in preview mode. That is structural, not an `if` check.

## Ghost writing

- Fires only at **semantic boundaries** — end of sentence, end of clause, newline, new list item — not on every keystroke. Full-width CJK punctuation counts.
- Never fires on delete, undo, redo, multiple cursors, or a non-empty selection.
- 500ms debounce, 4000 characters of context on each side (fill-in-the-middle), cached by `(prefix, suffix)`.
- Tab accepts, Esc dismisses. Typing on stays aligned with the suggestion and advances through it.

## Configuring completions

Settings takes four fields: Provider, Base URL, Model, API key.

For the official APIs, pick Anthropic or OpenAI and leave the Base URL at its default.

For a self-hosted OpenAI-compatible server (vLLM, Ollama, LM Studio), pick **OpenAI** and point the Base URL at your endpoint, for example `http://127.0.0.1:8000/v1`. If the server has no auth the key can be left blank; if it does, the key is required or you get `Unauthorized`.

**A note on reasoning models.** When vLLM runs with `--reasoning-parser`, the chain of thought goes into a `reasoning` field and `content` comes back `null` — a short completion's token budget is spent entirely on thinking and ghost text receives nothing. So the request body always carries `chat_template_kwargs: {"enable_thinking": false}`. The official OpenAI API ignores unknown top-level fields, so it is harmless there.

Only two protocols are supported: **Anthropic** and **OpenAI**. The latter is what vLLM, Ollama and LM Studio expose, so local models need no extra code — just point the base URL at them.

## Design notes

**One window, one WebView.** Each `WKWebView` is its own content process (30-60MB). One window per file does not survive a vault with hundreds of files, so switching files swaps the content instead.

**Switching files rebuilds `EditorState` rather than dispatching a transaction.** A transaction keeps the undo history: after A → B, `Cmd+Z` would pull A's text into B and the next save would corrupt B. The cost is no cross-file undo.

**The file tree is lazy.** A full recursive walk of a real notes directory (6,165 folders / 1,599 `.md` files) measured 0.81s — visible jank on the window-opening path. Reading one level is 2ms.

**Images go into `<document>.assets/`** (the Typora convention) and are linked by relative path, so the folder can be moved, synced or shared and the links still resolve. The type is sniffed from the **bytes**, not from what the clipboard claims — the two disagree often enough, and the extension has to match the real content or nothing renders. macOS screenshots arrive as TIFF and are converted to PNG.

Preview images are served over `nib-asset://`, with Swift reading the bytes. Relative paths would otherwise resolve against the bundle, and the page's read permission only covers the bundle's `web/`. A `<base>` tag is not an option — it would rewrite `./editor.css` and `./editor.js` too, and the app simply would not open. Requests are confined to the document's own directory: links are page content, and page content is not trusted.

## Tests

```
swift test           81 tests
cd web && npm test   75 tests
```

Swift covers response cleanup, endpoint assembly, file visibility and sorting, `.assets` path derivation, rename/create name validation, image type sniffing and name collisions, `nib-asset://` path-traversal rejection, appearance round-trips, and cross-file search.

JS covers ghost text trigger rules (including CJK punctuation and false-trigger guards), word counting (CJK counted by character, code excluded), image path rewriting, formatting string transforms, and outline parsing.

`wordcount.js`, `format.js`, `outline.js` and `preview.js` do not depend on CodeMirror, so their tests import the real implementations. `ghost.js` cannot — it is a CM extension — so one test there checks the rules stay in sync and keeps the docs from drifting from the code.

## Project

Project home: https://github.com/howtoexitvim/Nib

## License

[MIT](LICENSE)
