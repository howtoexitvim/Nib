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
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let editor = EditorViewController()
    private let sidebar = SidebarViewController()
    private let splitViewController = NSSplitViewController()

    private var workspace: Workspace?
    /// Debounces autosave while typing, so a write happens after a pause
    /// rather than on every keystroke.
    private var idleSaveTask: Task<Void, Never>?
    private static let idleSaveDelay = Duration.seconds(2)
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

        // An empty toolbar, purely for layout. With `.fullSizeContentView` and
        // no toolbar the content view fills the titlebar area, so the sidebar's
        // first rows are drawn under the traffic lights. A window-hosted
        // toolbar makes AppKit reserve the titlebar band and place the traffic
        // lights inside it, and `.unified` lets the split view's sidebar tint
        // run up behind it -- the same structural fix as ImageDedupe's
        // window-hosted toolbar, rather than nudging content down by a
        // hardcoded inset that has to be re-guessed on every OS.
        let toolbar = NSToolbar(identifier: "NibMainToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // Menu items send to nil so they travel the responder chain, and this
        // controller supplies the actions for them. No splicing is needed or
        // safe: AppKit already sets the content view controller's nextResponder
        // to the window, and NSWindow.nextResponder is its own windowController,
        // so this object is on the chain already. The previous
        //     nextResponder = contentViewController.nextResponder   // the window
        //     contentViewController.nextResponder = self
        // built a self -> window -> self loop instead, and the first unhandled
        // selector walked it until it hit the stack guard page -- a SIGSEGV
        // (KERN_PROTECTION_FAILURE) under a wall of AppKit forwardMethod frames.

        editor.onDirtyChange = { [weak self] dirty in
            self?.window?.isDocumentEdited = dirty
            if dirty { self?.scheduleIdleSave() }
        }
        sidebar.onSelect = { [weak self] url in
            self?.selectFile(url)
        }
        sidebar.attach(menu: makeContextMenu())
        editor.documentURL = { [weak self] in self?.currentFileURL }
        editor.onModeChange = { [weak self] _ in
            // Menu titles and enablement follow the mode, and AppKit only
            // re-validates when something prompts it.
            self?.window?.toolbar?.validateVisibleItems()
        }
        editor.onImageSaved = { [weak self] in
            guard let self, let url = self.currentFileURL else { return }
            // The .assets folder is hidden from the tree, but its parent may
            // now hold a folder it did not before.
            self.workspace?.reload(url.deletingLastPathComponent())
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

    /// Restarts the idle countdown. Typing keeps pushing it back; a pause
    /// lets it fire.
    private func scheduleIdleSave() {
        idleSaveTask?.cancel()
        idleSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.idleSaveDelay)
            guard !Task.isCancelled, let self else { return }
            await self.saveCurrentIfNeeded()
        }
    }

    /// Saves now, cancelling any pending idle save so it cannot write again
    /// on top of what just landed.
    func saveNow() async {
        idleSaveTask?.cancel()
        idleSaveTask = nil
        await saveCurrentIfNeeded()
    }

    // MARK: - File operations from the sidebar

    /// Built here rather than in the sidebar so the actions land on this
    /// controller directly, with no responder-chain hop for a menu that is
    /// only ever shown over one view.
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "New File", action: #selector(newFile(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "New Folder", action: #selector(newFolder(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Rename…", action: #selector(renameItem(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Move to Trash", action: #selector(trashItem(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealClicked(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    /// Where a new item belongs: inside the clicked folder, beside a clicked
    /// file, or at the root when the click missed every row.
    private func targetDirectory() -> URL? {
        guard let workspace else { return nil }
        guard let clicked = sidebar.targetFileURL else { return workspace.rootURL }
        return sidebar.targetNodeIsDirectory ? clicked : clicked.deletingLastPathComponent()
    }

    @objc func newFile(_ sender: Any?) {
        guard let workspace, let directory = targetDirectory() else { return }
        prompt(title: "New File", message: "Name for the new file:", value: "Untitled") { name in
            do {
                let url = try workspace.createFile(named: name, in: directory)
                self.selectFile(url)
            } catch {
                self.presentError(error, title: "Could not create the file")
            }
        }
    }

    @objc func newFolder(_ sender: Any?) {
        guard let workspace, let directory = targetDirectory() else { return }
        prompt(title: "New Folder", message: "Name for the new folder:", value: "Untitled Folder") { name in
            do {
                _ = try workspace.createFolder(named: name, in: directory)
            } catch {
                self.presentError(error, title: "Could not create the folder")
            }
        }
    }

    @objc func renameItem(_ sender: Any?) {
        guard let workspace, let url = sidebar.targetFileURL else { return }
        let isDirectory = sidebar.targetNodeIsDirectory
        let current = isDirectory
            ? url.lastPathComponent
            : (url.lastPathComponent as NSString).deletingPathExtension

        prompt(title: "Rename", message: "New name for \"\(current)\":", value: current) { name in
            do {
                let moved = try workspace.rename(url, to: name)
                // The open file moving out from under the editor would leave
                // the next save writing to a path that no longer exists.
                if self.currentFileURL == url.standardizedFileURL {
                    self.currentFileURL = moved.standardizedFileURL
                    self.updateTitle()
                    WorkspaceStore.saveFile(moved)
                    self.sidebar.select(moved)
                }
            } catch {
                self.presentError(error, title: "Could not rename \(url.lastPathComponent)")
            }
        }
    }

    @objc func trashItem(_ sender: Any?) {
        guard let workspace, let url = sidebar.targetFileURL else { return }
        // No confirmation: it goes to the Trash, so it is recoverable, and a
        // dialog on every delete is the kind of friction Typora does without.
        do {
            let wasOpen = currentFileURL == url.standardizedFileURL
            try workspace.trash(url)
            // A document's images are its own; leaving them orphans the folder.
            let assets = Workspace.assetsDirectory(for: url)
            if !sidebar.targetNodeIsDirectory,
               FileManager.default.fileExists(atPath: assets.path) {
                try? FileManager.default.trashItem(at: assets, resultingItemURL: nil)
            }
            if wasOpen { closeCurrentFile() }
        } catch {
            presentError(error, title: "Could not move \(url.lastPathComponent) to the Trash")
        }
    }

    @objc func revealClicked(_ sender: Any?) {
        guard let url = sidebar.targetFileURL ?? currentFileURL ?? workspace?.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Empties the editor after the open file goes away.
    private func closeCurrentFile() {
        currentFileURL = nil
        editor.setDocument("", path: "")
        editor.markSaved()
        WorkspaceStore.saveFile(nil)
        updateTitle()
    }

    /// A one-field sheet. AppKit has no text-input alert, so this is the
    /// standard accessory-view construction.
    private func prompt(
        title: String,
        message: String,
        value: String,
        onAccept: @escaping (String) -> Void
    ) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        field.placeholderString = "Name"
        alert.accessoryView = field
        // Without this the sheet opens with the buttons focused and typing
        // does nothing.
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            onAccept(name)
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

    // MARK: - Editing commands
    //
    // These forward to the web layer, which owns the buffer. They apply in
    // source mode only: the preview is a read-only projection with no cursor,
    // which is also what keeps ghost writing sound.

    @objc func performFind(_ sender: Any?) { editor.send("find") }
    @objc func performReplace(_ sender: Any?) { editor.send("replace") }
    @objc func formatBold(_ sender: Any?) { editor.send("bold") }
    @objc func formatItalic(_ sender: Any?) { editor.send("italic") }
    @objc func formatCode(_ sender: Any?) { editor.send("code") }
    @objc func formatLink(_ sender: Any?) { editor.send("link") }

    @objc func formatHeading(_ sender: Any?) {
        // The level rides on the menu item's tag, so one action serves all six
        // headings plus Paragraph.
        let level = (sender as? NSMenuItem)?.tag ?? 0
        editor.send("heading", String(level))
    }

    @objc func performFindInFolder(_ sender: Any?) {
        // Arrives with the search UI, in a later commit.
        NSSound.beep()
    }

    @objc func toggleOutline(_ sender: Any?) {
        // Arrives with the outline pane, in a later commit.
        NSSound.beep()
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

    // MARK: - Menu validation

    /// Greys out what cannot be done right now, and keeps toggle titles honest.
    ///
    /// Without this every item is always enabled, so Save on an empty window
    /// and Bold in the preview both look available and then do nothing.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let isSourceMode = editor.mode == "source"

        switch menuItem.action {
        case #selector(saveDocument(_:)):
            return currentFileURL != nil || editor.isDirty

        case #selector(renameItem(_:)), #selector(trashItem(_:)):
            return sidebar.targetFileURL != nil

        case #selector(newFile(_:)), #selector(newFolder(_:)),
             #selector(performFindInFolder(_:)):
            return workspace != nil

        case #selector(revealInFinder(_:)), #selector(revealClicked(_:)):
            return currentFileURL != nil || workspace != nil

        case #selector(performFind(_:)), #selector(performReplace(_:)),
             #selector(formatBold(_:)), #selector(formatItalic(_:)),
             #selector(formatCode(_:)), #selector(formatLink(_:)),
             #selector(formatHeading(_:)):
            // The preview has no cursor to act on.
            return isSourceMode && currentFileURL != nil

        case #selector(toggleRenderMode(_:)):
            menuItem.title = isSourceMode ? "Show Preview" : "Show Source"
            return currentFileURL != nil || editor.isDirty

        case #selector(toggleSidebar(_:)):
            menuItem.title = sidebarItem.isCollapsed ? "Show Sidebar" : "Hide Sidebar"
            return true

        default:
            return true
        }
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

    /// Leaving the window is a natural save point -- switching to another app
    /// and coming back should not find unsaved work.
    func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in await saveNow() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        idleSaveTask?.cancel()
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
