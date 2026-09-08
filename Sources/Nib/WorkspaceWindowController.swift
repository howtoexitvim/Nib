import AppKit
import UniformTypeIdentifiers

/// Why a save was abandoned.
enum EditorError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "The editor's contents could not be read, so nothing was written."
    }
}

/// The single window: a file tree beside one editor.
///
/// One window and one WebView, not one per file. Each `WKWebView` runs its own
/// content process at 30-60MB, so a window per file does not survive a folder
/// of any size. Switching files swaps the editor's contents instead.
@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
    private let editor = EditorViewController()
    private let sidebar = SidebarViewController()
    private let splitViewController = NSSplitViewController()

    private var workspace: Workspace?
    /// The file being edited. Lives here, not on `Workspace`, so the workspace
    /// stays a model with no editor state in it.
    private(set) var currentFileURL: URL?

    /// The window, retained for the app's lifetime. Registration happens after
    /// `init` returns: inserting `self` from inside an initializer does not
    /// keep a not-yet-formed object alive.
    private static var shared: WorkspaceWindowController?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.backgroundColor = .textBackgroundColor
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 400)

        super.init(window: window)

        window.delegate = self
        window.contentViewController = makeSplitView()
        // Setting contentViewController resizes the window to the view's
        // fitting size, so the intended frame is applied after it, not before.
        window.setContentSize(NSSize(width: 1060, height: 720))
        window.center()
        window.setFrameAutosaveName("NibMainWindow")

        editor.onDirtyChange = { [weak self] dirty in
            self?.window?.isDocumentEdited = dirty
        }
        sidebar.onSelect = { [weak self] url in
            self?.selectFile(url)
        }
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Nib builds its windows in code")
    }

    private func makeSplitView() -> NSViewController {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        // Without an autosave name the divider resets to the default on every
        // launch, which is exactly the kind of thing people notice.
        sidebarItem.holdingPriority = .init(260)

        let editorItem = NSSplitViewItem(viewController: editor)
        editorItem.minimumThickness = 420

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(editorItem)
        splitViewController.splitView.autosaveName = "NibSplitView"
        return splitViewController
    }

    private var sidebarItem: NSSplitViewItem { splitViewController.splitViewItems[0] }

    // MARK: - Opening

    /// Opens a folder as the workspace, replacing whatever was open.
    func openFolder(_ url: URL) {
        let workspace = Workspace(rootURL: url)
        self.workspace = workspace
        sidebar.show(workspace)
        WorkspaceStore.saveFolder(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        updateTitle()
    }

    /// The one path by which the open file changes.
    ///
    /// The current file is saved first, and a failed save cancels the switch --
    /// otherwise a write error would silently discard the edits as the buffer
    /// is replaced.
    func selectFile(_ url: URL) {
        guard url.standardizedFileURL != currentFileURL else { return }
        Task { @MainActor in
            guard await saveCurrentIfNeeded() else { return }
            load(url)
        }
    }

    private func load(_ url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            currentFileURL = url.standardizedFileURL
            editor.setDocument(text, path: url.path)
            updateTitle()
            sidebar.select(url)
            WorkspaceStore.saveFile(url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            presentError(error, title: "Could not open \(url.lastPathComponent)")
        }
    }

    /// Restores the last folder and file, or opens an empty workspace.
    func restoreSession() {
        if let folder = WorkspaceStore.loadFolder() {
            openFolder(folder)
            if let file = WorkspaceStore.loadFile(), file.path.hasPrefix(folder.path) {
                load(file)
            }
        }
    }

    // MARK: - Saving

    /// Writes the open file if it has unsaved edits. `true` means it is safe to
    /// move on -- nothing to save, or the save landed.
    @discardableResult
    func saveCurrentIfNeeded() async -> Bool {
        guard editor.isDirty, currentFileURL != nil else { return true }
        return await save()
    }

    /// Writes the buffer to the current file, reporting whether it landed.
    private func save() async -> Bool {
        guard let url = currentFileURL else { return false }
        // A failed read must abort the write: treating it as empty text would
        // truncate the user's file.
        guard let text = await editor.documentText() else {
            presentError(EditorError.unreadable, title: "Could not save \(url.lastPathComponent)")
            return false
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            editor.markSaved()
            updateTitle()
            return true
        } catch {
            presentError(error, title: "Could not save \(url.lastPathComponent)")
            return false
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard currentFileURL != nil else {
            saveDocumentAs(sender)
            return
        }
        Task { await save() }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Untitled.md"
        panel.directoryURL = workspace?.rootURL
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task { @MainActor in
                guard let text = await self.editor.documentText() else {
                    self.presentError(EditorError.unreadable, title: "Could not save \(url.lastPathComponent)")
                    return
                }
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    self.currentFileURL = url.standardizedFileURL
                    self.editor.markSaved()
                    self.updateTitle()
                    WorkspaceStore.saveFile(url)
                    self.workspace?.reload(url.deletingLastPathComponent())
                    self.sidebar.select(url)
                } catch {
                    self.presentError(error, title: "Could not save \(url.lastPathComponent)")
                }
            }
        }
    }

    // MARK: - Menu actions

    @objc func openFolderWithPanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            guard await saveCurrentIfNeeded() else { return }
            openFolder(url)
        }
    }

    @objc func toggleRenderMode(_ sender: Any?) {
        editor.toggleMode()
    }

    @objc func toggleSidebar(_ sender: Any?) {
        sidebarItem.animator().isCollapsed.toggle()
    }

    @objc func revealInFinder(_ sender: Any?) {
        guard let url = currentFileURL ?? workspace?.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Presentation

    private func updateTitle() {
        let name = currentFileURL?.lastPathComponent
            ?? workspace?.rootURL.lastPathComponent
            ?? "Nib"
        window?.title = name
        window?.subtitle = currentFileURL != nil
            ? (workspace?.rootURL.lastPathComponent ?? "")
            : ""
        window?.representedURL = currentFileURL
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

    // MARK: - Window lifecycle

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard editor.isDirty else { return true }
        // Auto-save, no prompt: refuse the close now and perform it once the
        // bytes are on disk.
        Task { @MainActor in
            if await saveCurrentIfNeeded() { self.close() }
        }
        return false
    }

    // MARK: - Static access

    /// The window, created on first use.
    static func main() -> WorkspaceWindowController {
        if let shared { return shared }
        let controller = WorkspaceWindowController()
        shared = controller
        return controller
    }

    static func present() {
        let controller = main()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// Opens a file or folder handed over by the Finder or the command line.
    static func open(url: URL) {
        let controller = main()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            controller.openFolder(url)
        } else {
            // A file opened on its own still needs a workspace, so its own
            // folder becomes one.
            if controller.workspace == nil {
                controller.openFolder(url.deletingLastPathComponent())
            }
            controller.selectFile(url)
        }
        present()
    }
}
