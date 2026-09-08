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

    override func loadView() {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(ScriptHandler(self), name: "completion")
        controller.add(ScriptHandler(self), name: "document")
        config.userContentController = controller
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

    // MARK: - Editor API

    func setDocument(_ text: String) {
        callJS("window.nib.setDoc(\(jsString(text)))")
    }

    func documentText() async -> String {
        await withCheckedContinuation { continuation in
            runWhenReady {
                self.webView.evaluateJavaScript("window.nib.getDoc()") { value, _ in
                    continuation.resume(returning: value as? String ?? "")
                }
            }
        }
    }

    func markSaved() {
        callJS("window.nib.markSaved()")
    }

    func toggleMode() {
        callJS("window.nib.toggleMode()")
    }

    func focusEditor() {
        callJS("window.nib.focus()")
    }

    // MARK: - Plumbing

    private func callJS(_ script: String) {
        runWhenReady { self.webView.evaluateJavaScript(script, completionHandler: nil) }
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
        if event == "dirty", let dirty = body["isDirty"] as? Bool {
            isDirty = dirty
            onDirtyChange?(dirty)
        }
    }
}

extension EditorViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        pendingAfterLoad.forEach { $0() }
        pendingAfterLoad.removeAll()
        focusEditor()
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
        case "document":
            owner?.handleDocumentEvent(body)
        default:
            break
        }
    }
}
