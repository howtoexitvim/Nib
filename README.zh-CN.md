<div align="center">

# Nib

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Markdown%20Editor-2563eb)
![Size](https://img.shields.io/badge/size-1.4MB-059669)

</div>

Nib 是一个 macOS 上的极简 Markdown 编辑器：原生 Swift 外壳包裹单个 WKWebView，里面跑 CodeMirror 6。

它带 **ghost writing**。在语义边界上——句子末尾、换行、新的列表项——由你自己配置的 LLM 给出灰色的续写建议，Tab 接受，Esc 忽略。服务由你配置，应用本身不内置任何模型。

API key 存在 Keychain 里，网络请求从 Swift 侧发出，key 不会进入 JavaScript 上下文。

## 安装

从 [releases 页面](https://github.com/howtoexitvim/Nib/releases)下载 zip，解压后把 `Nib.app` 拖进 `/Applications`。构建是 ad-hoc 签名、未经过公证的，所以需要清除一次隔离标记：

```bash
xattr -dr com.apple.quarantine /Applications/Nib.app
```

仅支持 Apple silicon（arm64）。最新版本为 **v0.1.0**。

也可以自己从源码构建——只需要 Swift 工具链和 Node。

## 构建

```bash
make        # 构建 web bundle 和 build/Nib.app
make run    # 构建并启动
make test   # Swift 测试 + JS 测试
make clean
```

没有 Xcode 工程。`swift build` 产出二进制，Makefile 手工组装 `.app`，全程在命令行中可复现。

产物约 **1.4MB**（Typora 是 46MB，Electron 应用通常在 150-250MB）。

## 两个模式

源码模式是 CodeMirror，预览模式是只读渲染。**源码是唯一真相，预览只是投影。** `Cmd+/` 在两者之间切换——快捷键绑在 window 上，所以两种模式下都生效。

预览不可编辑、也不处理输入，所以在预览模式下 ghost text **没有任何代码路径**可以触发。这是结构上的性质，不是靠 `if` 判断关掉的。

## Ghost writing

- 只在**语义边界**触发——句末、子句末、换行、新列表项——而不是每次按键。中文全角标点同样算在内。
- 删除、撤销、重做、多光标、有选区时都不触发。
- 500ms 防抖，前后各 4000 字符上下文（fill-in-the-middle），按 `(prefix, suffix)` 缓存。
- Tab 接受，Esc 忽略。继续打字时若与建议一致则保留建议并向前推进。

## 配置补全服务

设置里有四项：Provider、Base URL、Model、API key。

使用官方 API 时选 Anthropic 或 OpenAI，Base URL 保持默认即可。

使用自托管的 OpenAI 兼容服务（vLLM、Ollama、LM Studio）时选 **OpenAI**，把 Base URL 指向你的 endpoint，例如 `http://127.0.0.1:8000/v1`。服务没有开启鉴权时 key 可以留空；开了鉴权就必须填，否则会返回 `Unauthorized`。

**关于带 reasoning 的模型。** vLLM 挂上 `--reasoning-parser` 时，思考链会进入 `reasoning` 字段，而 `content` 返回 `null`——短补全的 token 预算会全部花在思考上，ghost text 什么也拿不到。所以请求体里固定带上 `chat_template_kwargs: {"enable_thinking": false}`。OpenAI 官方 API 会忽略不认识的顶层字段，对它无害。

只支持两种协议：**Anthropic** 和 **OpenAI**。后者正是 vLLM、Ollama、LM Studio 等自托管服务暴露的接口，所以本地模型不需要额外代码——把 base URL 指过去就行。

## 设计说明

**一个窗口，一个 WebView。** 每个 `WKWebView` 都是独立的 content process（30-60MB）。一个文件一个窗口在几百个文件的笔记库里撑不住，所以切换文件是换内容，而不是开新窗口。

**切换文件时重建 `EditorState`，而不是 dispatch 一个 transaction。** transaction 会保留 undo history：从 A 切到 B 之后按 `Cmd+Z`，会把 A 的文本拉进 B，下一次保存就写坏了 B。代价是没有跨文件的 undo。

**文件树是懒加载的。** 完整递归遍历一个真实的笔记目录（6,165 个目录 / 1,599 个 `.md` 文件）实测 0.81 秒——放在开窗路径上是肉眼可见的卡顿。只读一层是 2ms。

**粘贴的图片写进 `<文档名>.assets/`**（Typora 的约定），链接用相对路径，所以整个目录搬走、同步、分享之后链接依然有效。类型靠**字节**嗅探，而不是相信剪贴板声称的类型——两者并不总是一致，而扩展名必须和真实内容匹配，否则什么都渲染不出来。macOS 截图是 TIFF，会被转成 PNG。

预览里的图片走 `nib-asset://`，由 Swift 读取字节。否则相对路径会相对 bundle 解析，而且页面的读权限只覆盖 bundle 里的 `web/`。`<base>` 标签不是可行方案——它会连 `./editor.css` 和 `./editor.js` 一起重写，应用直接打不开。请求被限制在文档自身所在的目录内：链接是页面内容，而页面内容不可信。

## 测试

```
swift test           81 个
cd web && npm test   75 个
```

Swift 侧覆盖：响应清洗、endpoint 拼装、文件可见性与排序、`.assets` 路径推导、重命名/新建的命名校验、图片类型嗅探与命名冲突、`nib-asset://` 的路径穿越拒绝、外观设置往返、跨文件搜索。

JS 侧覆盖：ghost text 触发规则（含中文标点与防误触发）、字数统计（中文按字符计、排除代码）、图片路径重写、格式化的字符串变换、大纲解析。

`wordcount.js`、`format.js`、`outline.js`、`preview.js` 都不依赖 CodeMirror，所以测试直接 import 真实实现。`ghost.js` 做不到——它是 CM 扩展——所以那边用一条测试校验规则保持一致，防止文档与实现漂移。

## 项目

项目主页：https://github.com/howtoexitvim/Nib

## License

[MIT](LICENSE)
