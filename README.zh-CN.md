<div align="center">

# Nib

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Markdown%20Editor-2563eb)
![Size](https://img.shields.io/badge/size-1.4MB-059669)

</div>

Nib 是一个极简的 macOS Markdown 编辑器。它**只有约 1.4MB** —— Typora 是 46MB，Electron 编辑器通常在 150-250MB。

它是包裹着 CodeMirror 6 的原生 Swift 外壳。打开即用，不打扰你，并且提供了一件别的轻量编辑器没有的东西：幽灵写作。

在语义边界上 —— 一句话的结尾、新的一行、新的列表项 —— 你自己的大模型会提出一段灰色的续写。Tab 接受，Esc 忽略。它不会在每次敲键时触发，也绝不会在你删除、撤销或有选区时出现。

```
水壶已经烧了一会儿，而
                      ▏窗户上蒙了一层雾。   ← 按 Tab 接受
```

模型不内置。你自带模型，密钥始终留在钥匙串里。

## 为什么选择 Nib

- 🪶 **1.4MB**：一个真正的原生应用，而不是套了标题栏的浏览器。
- ✍️ **幽灵写作**：建议出现在一个念头结束的地方，而不是词语中间。
- 🔌 **自带模型**：支持 Anthropic 与 OpenAI 协议 —— 把 Base URL 指向本地服务，也就覆盖了自托管的 vLLM、Ollama 和 LM Studio。
- 🔒 **密钥留在钥匙串**：请求由 Swift 发出，密钥不会进入 JavaScript 环境。
- 📄 **两种模式**：源码与预览，`Cmd+/` 切换。预览模式在结构上无法触发幽灵写作。
- 🖼️ **移动后依然有效的图片**：粘贴的图片会存入文件旁的 `<document>.assets/` 文件夹并使用相对链接，移动或同步整个文件夹后链接依然可用。
- 🗂️ **侧边栏**：文件树、大纲与跨文件搜索。
- 🆓 **免费，MIT 许可**。

<!-- TODO: add screenshots of the editor, ghost text in action, and Settings -->

## 安装

从 [releases 页面](https://github.com/howtoexitvim/Nib/releases)下载 zip（当前版本 **v0.1.0**），解压后把 `Nib.app` 拖入 `/Applications`。

该构建使用 ad-hoc 签名，未经过公证，因此需要清除一次隔离标记：

```bash
xattr -dr com.apple.quarantine /Applications/Nib.app
```

仅支持 Apple 芯片。

## 配置补全

设置中有四项：Provider、Base URL、Model、API key。

使用官方 API 时，选择 Anthropic 或 OpenAI，Base URL 保持默认即可。使用自托管的 OpenAI 兼容服务时，选择 OpenAI 并把 Base URL 指向你的端点，例如 `http://127.0.0.1:8000/v1` —— 若服务端没有鉴权，密钥可以留空。

请求会带上 `chat_template_kwargs: {"enable_thinking": false}`，因此带推理解析器的模型也能正常返回补全内容。

## 构建

```bash
make        # 构建 web bundle 与 build/Nib.app
make run    # 构建并启动
make test   # Swift 测试 + JS 测试
```

不需要 Xcode 工程 —— 只需要 Swift 工具链和 Node。项目包含 81 个 Swift 测试与 75 个 JS 测试。

## 项目

项目主页：https://github.com/howtoexitvim/Nib

## License

[MIT](LICENSE)
