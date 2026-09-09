import AppKit
import WebKit

/// Hosts the CodeMirror editor in a WKWebView and brokers between it and the app.
///
/// The system WebView is what keeps launch fast and the bundle small -- this is
/// the same architecture Typora uses (native shell, system WebKit, web editor),
/// as opposed to shipping a whole Chromium.
final class EditorViewController: NSViewController {
    private var webView: WKWebView!
    private let completions = CompletionService()

    /// Set once the page has loaded; queued work runs after that.
    private var isReady = false
    private var pendingAfterLoad: [() -> Void] = []

    /// Mirrors the editor's dirty state for the window's close/save flow.
    private(set) var isDirty = false
    var onDirtyChange: ((Bool) -> Void)?
    /// Where the open document lives, so pasted images can be written beside
    /// it. A closure rather than a stored URL, so there is still exactly one
    /// place that knows which file is open.
    var documentURL: (() -> URL?)?
    /// An image landed on disk, so the sidebar can pick up the new folder.
    var onImageSaved: (() -> Void)?
    /// A link to a local file was clicked in the preview.
    var onOpenFile: ((URL) -> Void)?
    /// Which mode the editor is showing. The web layer is the authority --
    /// it owns the toggle -- and reports every change here.
    private(set) var mode: String = "source"
    var onModeChange: ((String) -> Void)?
    /// The document's headings changed, for the outline pane.
    var onOutlineChange: (([Heading], Int) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(ScriptHandler(self), name: "completion")
        controller.add(ScriptHandler(self), name: "document")
        controller.add(ScriptHandler(self), name: "log")
        // Forward console output and uncaught errors to the native log;
        // otherwise a failure inside the web layer is completely silent.
        controller.addUserScript(WKUserScript(
            source: Self.consoleBridge,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // The saved theme, injected before the page runs anything.
        //
        // applyAppearance goes through callJS, which queues until didFinish --
        // long after first paint -- so a dark-mode user saw a white flash on
        // every launch. A document-start user script sets the attribute the
        // stylesheet keys off before any CSS is applied.
        let theme = Appearance.load().theme
        if theme != .system {
            controller.addUserScript(WKUserScript(
                source: "document.documentElement.setAttribute('data-theme', '\(theme.rawValue)');",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        config.userContentController = controller
        // Serves the open document's images to the preview. Registered on the
        // configuration, which is why it has to be set before the WebView is
        // created -- a handler cannot be added afterwards.
        config.setURLSchemeHandler(
            AssetSchemeHandler(baseDirectory: { [weak self] in
                self?.documentURL?()?.deletingLastPathComponent()
            }),
            forURLScheme: AssetSchemeHandler.scheme
        )
        // The editor is local and offline; nothing should be cached to disk.
        config.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // The WebView must paint its own background: with drawsBackground off it
        // is fully transparent, and combined with a transparent titlebar the
        // whole window renders invisible.
        webView.allowsMagnification = false
        // Rubber-band scrolling on the whole page would drag the editor around;
        // CodeMirror does its own scrolling inside.
        webView.enclosingScrollView?.verticalScrollElasticity = .none
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") else {
            presentFatal("Editor resources are missing from the app bundle.")
            return
        }
        webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
    }

    /// Mirrors console output and uncaught errors back to the host.
    private static let consoleBridge = """
    (() => {
      const send = (level, parts) => {
        try {
          window.webkit.messageHandlers.log.postMessage({
            level,
            text: parts.map((p) => {
              if (typeof p === 'string') return p;
              try { return JSON.stringify(p); } catch { return String(p); }
            }).join(' '),
          });
        } catch {}
      };
      for (const level of ['log', 'warn', 'error']) {
        const original = console[level].bind(console);
        console[level] = (...args) => { send(level, args); original(...args); };
      }
      window.addEventListener('error', (e) => {
        send('error', [e.message + ' @ ' + e.filename + ':' + e.lineno]);
      });
      window.addEventListener('unhandledrejection', (e) => {
        send('error', ['unhandled rejection: ' + e.reason]);
      });
    })();
    """

    // MARK: - Editor API

    /// Replaces the buffer. `path` keys the editor's per-file cursor memory.
    func setDocument(_ text: String, path: String = "") {
        callJS("window.nib.setDoc(\(jsString(text)), \(jsString(path)))")
    }

    /// How long to wait for the page before giving up on reading the document.
    private static let documentReadTimeout = Duration.seconds(5)

    /// The editor's current text, or nil if it could not be read.
    ///
    /// Returning nil rather than "" matters: every caller writes this to disk,
    /// and mapping a failure to the empty string truncated the user's file.
    /// A timeout is needed too -- if the page never loads, the queued work
    /// never runs and the continuation would otherwise hang forever.
    func documentText() async -> String? {
        await withCheckedContinuation { continuation in
            // The continuation must resume exactly once even though both the
            // JS callback and the timeout can fire.
            let resumed = OneShot()

            runWhenReady { [weak self] in
                guard let self else {
                    resumed.resumeOnce(continuation, with: nil)
                    return
                }
                self.webView.evaluateJavaScript("window.nib.getDoc()") { value, error in
                    if let error {
                        NSLog("[nib] reading the document failed: %@", String(describing: error))
                    }
                    resumed.resumeOnce(continuation, with: value as? String)
                }
            }

            Task {
                try? await Task.sleep(for: Self.documentReadTimeout)
                resumed.resumeOnce(continuation, with: nil)
            }
        }
    }

    func markSaved() {
        callJS("window.nib.markSaved()")
    }

    /// Sends a command to the editor. The web layer owns the buffer, so every
    /// editing action is expressed as a message rather than performed here.
    func send(_ command: String, _ argument: String? = nil) {
        let arg = argument.map { jsString($0) } ?? "null"
        callJS("window.nib.command(\(jsString(command)), \(arg))")
    }

    /// Puts the cursor on a line, for the outline pane.
    func scrollToLine(_ line: Int) {
        callJS("window.nib.scrollToLine(\(line))")
    }

    /// Pushes theme and typography into the page.
    func applyAppearance(_ appearance: Appearance) {
        let data = try? JSONSerialization.data(withJSONObject: appearance.payload)
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        callJS("window.nib.applyAppearance(\(json))")
    }

    func toggleMode() {
        callJS("window.nib.toggleMode()")
    }

    func focusEditor() {
        callJS("window.nib.focus()")
    }

    // MARK: - Plumbing

    private func callJS(_ script: String) {
        // [weak self]: a window closed while its page is still loading would
        // otherwise keep this controller alive through the queue.
        runWhenReady { [weak self] in
            self?.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func runWhenReady(_ work: @escaping () -> Void) {
        if isReady { work() } else { pendingAfterLoad.append(work) }
    }

    /// JSON-encodes a Swift string for safe interpolation into JS.
    private func jsString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
        guard let data, let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast()) // strip the [ ] wrapper
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Nib could not start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }

    fileprivate func handleCompletion(id: Int, prefix: String, suffix: String) {
        Task {
            do {
                let text = try await completions.complete(prefix: prefix, suffix: suffix)
                deliver(id: id, text: text, error: nil)
            } catch {
                // Failures are surfaced to the console rather than as a dialog:
                // a completion is advisory, and interrupting writing with an
                // alert on every network hiccup would be worse than silence.
                deliver(id: id, text: "", error: error.localizedDescription)
            }
        }
    }

    private func deliver(id: Int, text: String, error: String?) {
        let errorArg = error.map { jsString($0) } ?? "null"
        callJS("window.nib.deliverCompletion(\(id), \(jsString(text)), \(errorArg))")
    }

    fileprivate func handleDocumentEvent(_ body: [String: Any]) {
        guard let event = body["event"] as? String else { return }
        switch event {
        case "dirty":
            if let dirty = body["isDirty"] as? Bool {
                isDirty = dirty
                onDirtyChange?(dirty)
            }
        case "mode":
            if let mode = body["mode"] as? String {
                self.mode = mode
                onModeChange?(mode)
            }
        case "outline":
            let raw = body["headings"] as? [[String: Any]] ?? []
            let headings = raw.compactMap { entry -> Heading? in
                guard let level = entry["level"] as? Int,
                      let text = entry["text"] as? String,
                      let line = entry["line"] as? Int
                else { return nil }
                return Heading(level: level, text: text, line: line)
            }
            onOutlineChange?(headings, body["active"] as? Int ?? -1)
        case "pasteImage":
            if let id = body["id"] as? Int, let data = body["data"] as? String {
                handlePastedImage(id: id, base64: data)
            }
        default:
            break
        }
    }

    /// Writes a pasted image and hands back the Markdown that references it.
    ///
    /// The controller does not know where the document lives, so it asks --
    /// keeping the current file in one place rather than mirroring it here.
    private func handlePastedImage(id: Int, base64: String) {
        guard let data = Data(base64Encoded: base64) else {
            deliverImage(id: id, markdown: "", error: "The pasted image could not be decoded.")
            return
        }
        do {
            let markdown = try ImageStore.save(data, forDocument: documentURL?())
            deliverImage(id: id, markdown: markdown, error: nil)
            onImageSaved?()
        } catch {
            deliverImage(id: id, markdown: "", error: error.localizedDescription)
        }
    }

    private func deliverImage(id: Int, markdown: String, error: String?) {
        let errorArg = error.map { jsString($0) } ?? "null"
        callJS("window.nib.deliverImage(\(id), \(jsString(markdown)), \(errorArg))")
    }
}

extension EditorViewController: WKNavigationDelegate {
    /// Keeps the editor from navigating away from itself.
    ///
    /// A link clicked in the preview would otherwise load that page *in place
    /// of the editor*, leaving the app showing a website with no way back.
    /// External links go to the browser; nothing else is allowed to navigate.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            // The initial load of the bundled page, and nothing else.
            return .allow
        }
        switch Self.route(url) {
        case .openExternally: NSWorkspace.shared.open(url)
        case .openInEditor: onOpenFile?(url.standardizedFileURL)
        case .ignore: break
        }
        return .cancel
    }

    /// Where a clicked link should go. Separated from the delegate so the
    /// decision is testable without a WebView.
    enum LinkDestination: Equatable { case openExternally, openInEditor, ignore }

    static func route(_ url: URL) -> LinkDestination {
        if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
            return .openExternally
        }
        if url.isFileURL { return .openInEditor }
        // Anything else -- javascript:, data:, an unknown scheme -- is not
        // something a note should be able to launch.
        return .ignore
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // A reload invalidates the loaded page, so queued work must wait again
        // rather than run against a document that is being torn down.
        isReady = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        drainQueue()
        focusEditor()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleLoadFailure(error)
    }

    /// Runs queued work so no caller waits forever, then reports the failure.
    ///
    /// The queued closures still run: each one is responsible for coping with a
    /// page that is not there, and a `documentText()` waiter must be released so
    /// its continuation resolves rather than hanging until the timeout.
    private func handleLoadFailure(_ error: Error) {
        NSLog("[nib] the editor page failed to load: %@", String(describing: error))
        drainQueue()
    }

    private func drainQueue() {
        let queued = pendingAfterLoad
        pendingAfterLoad.removeAll()
        queued.forEach { $0() }
    }
}


/// Resumes a continuation at most once.
///
/// `documentText()` races a JavaScript callback against a timeout; whichever
/// arrives second must be ignored, because resuming a checked continuation
/// twice is a runtime trap.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resumeOnce(_ continuation: CheckedContinuation<String?, Never>, with value: String?) {
        lock.lock()
        let alreadyDone = done
        done = true
        lock.unlock()
        guard !alreadyDone else { return }
        continuation.resume(returning: value)
    }
}

/// Bridges WKScriptMessage into the controller without creating a retain cycle
/// (WKUserContentController holds its handlers strongly).
private final class ScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var owner: EditorViewController?

    init(_ owner: EditorViewController) {
        self.owner = owner
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch message.name {
        case "completion":
            guard
                let id = body["id"] as? Int,
                let prefix = body["prefix"] as? String,
                let suffix = body["suffix"] as? String
            else { return }
            owner?.handleCompletion(id: id, prefix: prefix, suffix: suffix)
        case "log":
            let level = body["level"] as? String ?? "log"
            let text = body["text"] as? String ?? ""
            NSLog("[nib.web.%@] %@", level, text)
        case "document":
            owner?.handleDocumentEvent(body)
        default:
            break
        }
    }
}
