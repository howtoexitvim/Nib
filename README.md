# Nib（实现仓库）

macOS 极简 Markdown 编辑器。原生 Swift 外壳 + WKWebView + CodeMirror 6。

## 构建

```bash
make        # 构建 web bundle 和 build/Nib.app
make run    # 构建并启动
make test   # Swift 测试 + JS 测试
make clean
```

不需要 Xcode 工程：`swift build` 出二进制，Makefile 手工组装 .app,全程命令行可复现。

产物约 **1.3MB**（Typora 46MB，Electron 应用通常 150-250MB）。

## 结构

```text
Sources/Nib/
  AppDelegate.swift                   应用入口、菜单动作
  MenuBuilder.swift                   菜单栏（动作走 responder chain）
  WorkspaceWindowController.swift     唯一的窗口：当前文件、保存生命周期、菜单校验
  SidebarContainerViewController.swift 侧边栏容器（Files / Outline / Search）
  SidebarViewController.swift         文件树（NSOutlineView）
  OutlineViewController.swift         标题大纲
  SearchViewController.swift          跨文件搜索界面
  EditorViewController.swift          WKWebView 宿主 + JS 桥（全应用只有一个）
  Workspace.swift                     文件夹与懒加载的树；增删改都在这里
  FileNode.swift                      树节点 + 可见性/排序规则（纯函数）
  WorkspaceStore.swift                上次的文件夹与文件（security-scoped bookmark）
  ImageStore.swift                    粘贴的图片：类型嗅探、TIFF 转码、命名
  AssetSchemeHandler.swift            nib-asset:// 把本地图片喂给预览
  FileSearchService.swift             跨文件搜索（actor + AsyncStream）
  Appearance.swift                    主题与排版
  CompletionService.swift             补全请求（Anthropic / OpenAI 两种协议）
  Provider.swift                      provider 配置与 endpoint 拼装
  Keychain.swift                      API key 存取
  SettingsWindowController.swift      设置窗口

web/src/
  main.js       编辑器入口、两种模式切换
  state.js      EditorState 工厂（切换文件要重建 state，见下）
  ghost.js      ghost text 扩展（触发策略、Tab 接受、Esc 忽略）
  commands.js   菜单命令派发表
  format.js     加粗/斜体/链接/标题（纯字符串变换 + CM 命令）
  outline.js    标题解析
  wordcount.js  字数统计（中文按字符计，不依赖 CodeMirror）
  preview.js    渲染与图片路径重写
  paste.js      粘贴图片
  theme.js      外观设置
  bridge.js     与 Swift 通信
  editor.css    视觉系统
```

**一个窗口，一个 WebView。** 每个 `WKWebView` 是独立 content process（30-60MB），一个文件一个窗口在几百个文件的笔记库里撑不住。切换文件是换内容。

**切换文件重建 `EditorState`，不是 dispatch transaction。** transaction 会保留 undo history：A 切到 B 后按 ⌘Z 会把 A 的文本拉进 B，下次保存就写坏了 B。代价是没有跨文件 undo。

**树是懒加载的。** 完整递归遍历一个真实笔记目录（6,165 个目录 / 1,599 个 md）实测 0.81 秒，放在开窗路径上是肉眼可见的卡顿；只读一层是 2ms。

## 两个模式

源码模式是 CodeMirror，预览模式是只读渲染。**源码是唯一真相,预览是投影。** `Cmd+/` 切换（快捷键绑在 window 上，两种模式下都生效）。

预览不可编辑、无输入处理，所以 ghost text 在渲染模式下**没有代码路径可以触发** —— 这不是靠 if 判断关掉的，是结构上不存在。

## Ghost writing

触发策略见 `../docs/ghost-writing.md`。要点：

- 只在**语义边界**触发（句末、子句末、换行、新列表项），不是每个键。含中文全角标点。
- 删除、撤销、重做、多光标、有选区时**不触发**。
- 500ms 防抖，前后各 4000 字符上下文（fill-in-the-middle），按 `(prefix, suffix)` 缓存。
- Tab 接受，Esc 忽略，继续打字若与建议一致则保留并前移。

**API key 存 Keychain，网络请求在 Swift 侧发出**，key 不进 JS 上下文。

## 用本地 Qwen 测 ghost writing

H800 上跑着 vLLM，实测可用。**服务只监听 127.0.0.1，所以需要 SSH 隧道。**

```bash
# 1. 开隧道，保持这个终端不关
ssh -N -L 8100:127.0.0.1:8100 h800

# 2. 拿 key（它在 vllm 进程的环境变量里，不在任何配置文件里）
ssh h800 "tr '\0' '\n' < /proc/\$(pgrep -f 'vllm serve' | head -1)/environ | grep '^VLLM_API_KEY=' | cut -d= -f2"
```

然后在 Nib 的 Settings 里填：

| 字段 | 值 |
|---|---|
| Provider | **OpenAI**（vLLM 说的是 OpenAI 协议） |
| Base URL | `http://127.0.0.1:8100/v1` |
| Model | `qwen3.8-27b` |
| API key | 上面那条命令输出的字符串 |

**key 不能留空。** 这个部署开了鉴权，空 key 会返回 `{"error":"Unauthorized"}`。

实测输出（就是 Nib 真正会发的那个 prompt）：

```
英文散文   7.8s  →  "you write in plain Markdown and see the rendered
                     result instantly, with no distractions or complex UI."
中文散文   0.3s  →  "阳光透过玻璃窗洒在桌面上，看着街上来来往往的人，心里觉得格外平静。"
列表项     0.2s  →  "- 检查并修复标题栏的样式问题"
句子中间   0.1s  →  "source of truth"
```

中文续中文、列表里出列表项、句子中间接句子中间——都对。首次请求 7.8s 是冷启动，之后 0.1-0.3s，远小于 500ms 防抖。

**一个必须的请求参数：** 这个模型带 `--reasoning-parser qwen3`，vLLM 会把思考链放进 `reasoning` 字段并让 `content` 是 `null`——短补全的 token 预算会全花在思考上，ghost text 什么也拿不到。所以请求体里带了 `chat_template_kwargs: {"enable_thinking": false}`。OpenAI 官方 API 会忽略不认识的顶层字段，所以这个参数对它无害。

服务端信息（2026-09-09 实机核验）：`Qwen3.8-27B`，2×H800 tensor-parallel，`max-model-len` 262144，vLLM 0.27.1。

## 协议支持

只支持两种官方协议：**Anthropic** 和 **OpenAI**。后者是 vLLM、Ollama、LM Studio 等自托管服务暴露的接口，所以本地模型不需要额外代码 —— 在设置里把 base URL 指过去、key 留空即可。

## 图片

粘贴的图片写进 `<文档名>.assets/`（Typora 约定），链接是相对路径 —— 目录整体搬走、同步、分享，链接都还在。Typora 的另一个选项是绝对路径指向 `~/Library/Application Support/typora-user-images/`，文件一旦离开这台机器就断。

类型靠**字节**嗅探，不信剪贴板声称的类型：两者并不总是一致，而扩展名必须和真实内容匹配否则什么都渲染不出来。macOS 截图是 TIFF，会转成 PNG —— TIFF 出了苹果生态基本没法看。

预览里的图片走 `nib-asset://` 由 Swift 读字节。相对路径本来是相对 bundle 解析的，而且页面的读权限只给了 bundle 的 `web/`，两个问题都得解决。**不能用 `<base>` 标签** —— 它会同时重写 `./editor.css` 和 `./editor.js`，app 直接打不开。请求限制在文档所在目录内：链接是页面内容，页面内容不可信。

## 测试

```
swift test           66 个
cd web && npm test   53 个
```

Swift 侧：响应清洗、endpoint 拼装、文件可见性与排序、`.assets` 路径推导、重命名/新建的命名校验、图片类型嗅探与命名冲突、`nib-asset://` 的路径穿越拒绝、外观设置往返、跨文件搜索。

JS 侧：ghost text 触发规则（含中文标点、防误触发）、字数统计（中文按字符、排除代码）、图片路径重写、格式化字符串变换、大纲解析。

`wordcount.js`、`format.js`、`outline.js`、`preview.js` 都不依赖 CodeMirror，所以测试直接 import 真实实现。`ghost.js` 做不到（它是 CM 扩展），那边用一条测试校验规则一致，防止文档与实现漂移。
