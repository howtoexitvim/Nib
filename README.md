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

产物约 **800KB**（Typora 46MB，Electron 应用通常 150-250MB）。

## 结构

```text
Sources/Nib/
  AppDelegate.swift             应用入口、菜单动作
  MenuBuilder.swift             菜单栏（动作走 responder chain）
  DocumentWindowController.swift 一个窗口一个文件：开、存、另存、脏标记
  EditorViewController.swift    WKWebView 宿主 + JS 桥
  CompletionService.swift       补全请求（Anthropic / OpenAI 两种协议）
  Provider.swift                provider 配置与 endpoint 拼装
  Keychain.swift                API key 存取
  SettingsWindowController.swift 设置窗口

web/src/
  main.js       编辑器入口、两种模式切换
  ghost.js      ghost text 扩展（触发策略、Tab 接受、Esc 忽略）
  bridge.js     与 Swift 通信
  editor.css    视觉系统
```

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

## 协议支持

只支持两种官方协议：**Anthropic** 和 **OpenAI**。后者是 vLLM、Ollama、LM Studio 等自托管服务暴露的接口，所以本地模型不需要额外代码 —— 在设置里把 base URL 指过去、key 留空即可。

## 测试

```
swift test           15 个：响应清洗、endpoint 拼装
cd web && npm test   10 个：触发规则（含中文标点、防误触发）
```

JS 测试里有一条会校验测试中的规则和 `ghost.js` 里实际的规则一致，防止文档与实现漂移。
