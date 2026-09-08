import AppKit
import UniformTypeIdentifiers

/// Why a save was abandoned.
enum EditorError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "The editor's contents could not be read, so nothing was written."
    }
}

/// One window, one Markdown file.
///
/// File handling is deliberately plain: open, save, save-as, and a dirty flag.
/// No autosave, no versions, no document browser -- this is a text editor.
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    private let editor = EditorViewController()
    private var fileURL: URL?

    /// Open windows, retained here so they outlive the call that created them.
    /// Registration happens after `init` returns -- inserting `self` from inside
    /// an initializer does not keep a not-yet-formed object alive.
    private static var open: [DocumentWindowController] = []

    /// Designated, not convenience: `DocumentWindowController()` would otherwise
    /// resolve to NSWindowController's inherited no-arg initializer and produce
    /// a controller with no window at all.
    init(fileURL: URL?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        // Matches the editor's own background so the titlebar area does not
        // show through as a differently-coloured strip.
        window.backgroundColor = .textBackgroundColor
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 480, height: 360)
        window.tabbingMode = .preferred

        self.fileURL = fileURL
        super.init(window: window)

        window.delegate = self
        // Setting contentViewController resizes the window to the view's fitting
        // size, so the intended frame has to be applied after this, not before.
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 860, height: 720))
        window.center()
        editor.onDirtyChange = { [weak self] dirty in
            self?.window?.isDocumentEdited = dirty
        }

        if let fileURL { load(fileURL) } else { updateTitle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Nib builds its windows in code")
    }

    // MARK: - File operations

    private func load(_ url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            editor.setDocument(text)
            updateTitle()
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            presentError(error, title: "Could not open \(url.lastPathComponent)")
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let fileURL else {
            saveDocumentAs(sender)
            return
        }
        write(to: fileURL)
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.write(to: url)
        }
    }

    /// Saves to the current file, reporting whether it landed.
    ///
    /// Used by flows that must only proceed once the bytes are on disk, such as
    /// closing the window.
    private func saveAndReportSuccess() async -> Bool {
        guard let fileURL else { return false }
        guard let text = await editor.documentText() else {
            presentError(EditorError.unreadable, title: "Could not save \(fileURL.lastPathComponent)")
            return false
        }
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            editor.markSaved()
            updateTitle()
            NSDocumentController.shared.noteNewRecentDocumentURL(fileURL)
            return true
        } catch {
            presentError(error, title: "Could not save \(fileURL.lastPathComponent)")
            return false
        }
    }

    private func write(to url: URL) {
        Task { @MainActor in
            // A failed read must abort the write. Treating it as empty text
            // would truncate the user's file.
            guard let text = await editor.documentText() else {
                presentError(
                    EditorError.unreadable,
                    title: "Could not save \(url.lastPathComponent)"
                )
                return
            }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                fileURL = url
                editor.markSaved()
                updateTitle()
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                presentError(error, title: "Could not save \(url.lastPathComponent)")
            }
        }
    }

    private func updateTitle() {
        window?.title = fileURL?.lastPathComponent ?? "Untitled"
        window?.representedURL = fileURL
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Menu actions

    @objc func toggleRenderMode(_ sender: Any?) {
        editor.toggleMode()
    }

    // MARK: - Window lifecycle

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard editor.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to \(fileURL?.lastPathComponent ?? "Untitled")?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // The write is async, so refuse the close now and perform it in the
            // completion. The previous version returned false and never closed
            // the window at all.
            Task { @MainActor in
                if await saveAndReportSuccess() { self.close() }
            }
            return false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }

    // MARK: - Static helpers

    static func newDocument() {
        present(DocumentWindowController(fileURL: nil))
    }

    /// Retains the controller, then shows it.
    private static func present(_ controller: DocumentWindowController) {
        open.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    static func open(url: URL) {
        // Bring an already-open window forward rather than opening it twice.
        if let existing = open.first(where: { $0.fileURL == url }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        present(DocumentWindowController(fileURL: url))
    }

    static func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText,
        ]
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { open(url: $0) }
    }
}
