<div align="center">

# Nib

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Markdown%20Editor-2563eb)
![Size](https://img.shields.io/badge/size-1.4MB-059669)

</div>

Nib is a minimal Markdown editor for macOS. It weighs **about 1.4MB** — Typora is 46MB, and Electron editors are typically 150-250MB.

It is a native Swift shell around CodeMirror 6. It opens instantly, stays out of the way, and gives you one thing no other small editor does: ghost writing.

At semantic boundaries — the end of a sentence, a new line, a new list item — your own LLM proposes a grey continuation. Tab accepts it. Esc dismisses it. It does not fire on every keystroke, and never while you are deleting, undoing, or holding a selection.

```
The kettle had been on for a while now, and
                                            ▏the window was fogged over.   ← Tab to accept
```

Nothing is built in. You bring your own model, and the key never leaves the Keychain.

## Why Nib

- 🪶 **1.4MB**: a real native app, not a browser with a title bar.
- ✍️ **Ghost writing**: suggestions arrive where a thought ends, not mid-word.
- 🔌 **Your model**: Anthropic or OpenAI protocol — which also covers self-hosted vLLM, Ollama and LM Studio by pointing the base URL at them.
- 🔒 **Key stays in the Keychain**: requests are issued from Swift, so the key never enters the JavaScript context.
- 📄 **Two modes**: source and preview, toggled with `Cmd+/`. Ghost writing structurally cannot fire in preview.
- 🖼️ **Images that survive a move**: pasted images land in a `<document>.assets/` folder next to the file with relative links, so syncing or moving the folder keeps them working.
- 🗂️ **Sidebar**: file tree, outline, and cross-file search.
- 🆓 **Free and MIT licensed**.

<!-- TODO: add screenshots of the editor, ghost text in action, and Settings -->

## Install

Download the zip from the [releases page](https://github.com/howtoexitvim/Nib/releases) (current release **v0.1.0**), unzip it, and drag `Nib.app` into `/Applications`.

The build is ad-hoc signed and not notarized, so clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Nib.app
```

Apple silicon only.

## Configure completions

Settings takes four fields: Provider, Base URL, Model, API key.

For the official APIs, pick Anthropic or OpenAI and leave the Base URL at its default. For a self-hosted OpenAI-compatible server, pick OpenAI and point the Base URL at your endpoint, for example `http://127.0.0.1:8000/v1` — the key can be left blank if the server has no auth.

Requests carry `chat_template_kwargs: {"enable_thinking": false}`, so models with a reasoning parser still return usable completions.

## Build

```bash
make        # build the web bundle and build/Nib.app
make run    # build and launch
make test   # Swift tests + JS tests
```

No Xcode project needed — just a Swift toolchain and Node. There are 81 Swift tests and 75 JS tests.

## Project

Project home: https://github.com/howtoexitvim/Nib

## License

[MIT](LICENSE)

