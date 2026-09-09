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
    private let sidebarContainer = SidebarContainerViewController()
    /// The file tree, which most of this controller talks to directly.
    private var sidebar: SidebarViewController { sidebarContainer.files }
    private let splitViewController = NSSplitViewController()

    private var workspace: Workspace?
    private var appearance = Appearance.load()
    /// Debounces autosave while typing, so a write happens after a pause
    /// rather than on every keystroke.
    private var idleSaveTask: Task<Void, Never>?
    /// From Settings; 0 means no save while typing, only on leaving.
    private var idleSaveDelay: Duration { .seconds(appearance.idleSaveSeconds) }
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
            // No .fullSizeContentView: the content is meant to sit *below* the
            // titlebar, not run up through it. With it on and a transparent
            // titlebar, the editor pane owned the strip across the top and
            // there was nothing there to drag the window by -- only the
            // sidebar, which paints that area itself, appeared draggable.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Opaque, so the titlebar reads as one continuous bar across the whole
        // window the way Typora's does, rather than as two differently
        // coloured halves meeting at the split divider.
        window.titlebarAppearsTransparent = false
        // Not .textBackgroundColor: it is close to the page's --nib-bg but not
        // equal, so the native frame and the web content met at a visible seam.
        window.backgroundColor = Appearance.paper
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 400)
        // No native window tabs. The sidebar is already the navigation
        // surface; a tab bar would be a second one competing with it, and
        // Typora has none either. This also keeps AppKit from adding
        // "Show Tab Bar" to the View menu.
        window.tabbingMode = .disallowed

        super.init(window: window)

        window.delegate = self
        window.contentViewController = makeSplitView()
        // Setting contentViewController resizes the window to the view's
        // fitting size, so the intended frame is applied after it, not before.
        window.setContentSize(NSSize(width: 1060, height: 720))
        window.center()
        window.setFrameAutosaveName("NibMainWindow")

        // An empty toolbar, purely so AppKit reserves a titlebar band across
        // the whole window with the traffic lights inside it.
        //
        // It holds no items, so View > Show Toolbar would add a second, blank
        // row under the title and make the titlebar taller for nothing --
        // hence allowsUserCustomization stays off and the item is removed from
        // the View menu entirely. .unifiedCompact keeps the band at 38pt,
        // matching Typora; .unified leaves 52.
        let toolbar = NSToolbar(identifier: "NibMainToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        toolbar.centeredItemIdentifier = .documentTitle
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        // Hidden, and drawn as a centred toolbar item instead. AppKit centres
        // its own title within the area *right of the sidebar*, which puts it
        // visibly off-centre in the window.
        //
        // An earlier attempt at this produced two stacked titles and a taller
        // band, because the window title was left visible and .unifiedCompact
        // drew it as well. Hiding it is what makes the custom item the only
        // title; window.title is still set, for the Window menu and Mission
        // Control.
        window.titleVisibility = .hidden

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
            self?.updateTitle()
            if dirty { self?.scheduleIdleSave() }
        }
        sidebar.onSelect = { [weak self] url in
            self?.selectFile(url)
        }
        sidebar.attach(menu: makeContextMenu())
        // Through applyAppearance, not by assigning the window directly: the
        // app-level appearance has to be set on the launch path too, or every
        // detached panel and the Settings window follow the OS until the user
        // happens to change the theme.
        applyAppearance()
        // Settings applies appearance live, so it needs a way back to the
        // window that owns the editor.
        SettingsWindowController.onAppearanceChange = { [weak self] updated in
            self?.appearance = updated
            self?.applyAppearance()
        }
        sidebarContainer.outline.onSelect = { [weak self] heading in
            self?.editor.scrollToLine(heading.line)
        }
        editor.onOutlineChange = { [weak self] headings, active in
            self?.sidebarContainer.outline.show(headings, active: active)
        }
        editor.onOpenFile = { [weak self] url in
            guard let self else { return }
            // Only markdown, and only inside the workspace: a link should not
            // be able to pull arbitrary files into the editor.
            guard FileNode.markdownExtensions.contains(url.pathExtension.lowercased()),
                  let root = self.workspace?.rootURL,
                  url.path.hasPrefix(root.path + "/") || url.path == root.path
            else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
            self.selectFile(url)
        }
        sidebarContainer.search.rootURL = { [weak self] in self?.workspace?.rootURL }
        sidebarContainer.search.onSelect = { [weak self] hit in
            guard let self else { return }
            let query = self.sidebarContainer.search.currentQuery
            if hit.url.standardizedFileURL == self.currentFileURL {
                self.editor.scrollToLine(hit.line - 1, selecting: query)
            } else {
                // The file has to be loaded before there is a line to go to.
                self.selectFile(hit.url, thenScrollTo: hit.line - 1, selecting: query)
            }
        }
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
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarContainer)
        // A sidebar item defaults to running full height, up behind the
        // titlebar -- which puts its first control underneath the traffic
        // lights. Turning that off lets the toolbar own the titlebar band and
        // the sidebar start below it, with no hardcoded inset to re-guess.
        // The sidebar stops at the titlebar rather than running up behind it,
        // which is what keeps the bar unbroken across the full width.
        sidebarItem.allowsFullHeightLayout = false
        sidebarItem.titlebarSeparatorStyle = .none
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

    /// "doc.md — Saved", centred over the whole window rather than over the
    /// editor pane. One line: a stacked title and subtitle needs a taller
    /// titlebar and wastes the width that is already there.
    private let titleLabel: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.alignment = .center
        field.lineBreakMode = .byTruncatingMiddle
        field.cell?.usesSingleLineMode = true
        return field
    }()

    // MARK: - Opening

    /// Opens a folder as the workspace, replacing whatever was open.
    func openFolder(_ url: URL) {
        let workspace = Workspace(rootURL: url)
        self.workspace = workspace
        sidebar.show(workspace)
        sidebarContainer.setWorkspaceName(url.lastPathComponent)
        WorkspaceStore.saveFolder(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        updateTitle()
    }

    /// The one path by which the open file changes.
    ///
    /// The current file is saved first, and a failed save cancels the switch --
    /// otherwise a write error would silently discard the edits as the buffer
    /// is replaced.
    func selectFile(_ url: URL, thenScrollTo line: Int? = nil, selecting match: String? = nil) {
        guard url.standardizedFileURL != currentFileURL else {
            if let line { editor.scrollToLine(line, selecting: match) }
            return
        }
        Task { @MainActor in
            guard await saveCurrentIfNeeded() else { return }
            load(url)
            if let line { editor.scrollToLine(line, selecting: match) }
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
    ///
    /// An untitled buffer has nowhere to write, so the silent triggers (idle,
    /// blur, file switch) skip it rather than prompting mid-typing.
    /// `saveBeforeLeaving()` is the one that asks.
    @discardableResult
    func saveCurrentIfNeeded() async -> Bool {
        guard editor.isDirty, currentFileURL != nil else { return true }
        return await save()
    }

    /// Saves on the way out, asking where to put an untitled buffer.
    ///
    /// Typora's behaviour: autosave never interrupts, but closing or quitting
    /// with unsaved work in a document that has no file yet puts up Save As
    /// rather than silently dropping it. Returns false only when the user
    /// cancelled, which means "do not leave".
    func saveBeforeLeaving() async -> Bool {
        // A pending idle save would otherwise fire after this decision.
        idleSaveTask?.cancel()
        idleSaveTask = nil
        guard editor.isDirty else { return true }
        if currentFileURL != nil { return await save() }

        let alert = NSAlert()
        alert.messageText = "Save this document before closing?"
        alert.informativeText = "It has never been saved, so Nib does not know where to put it."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response: NSApplication.ModalResponse
        if let window {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        switch response {
        case .alertFirstButtonReturn: return await saveAs()
        case .alertSecondButtonReturn: return true
        default: return false
        }
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
        Task { await saveAs() }
    }

    /// Runs the Save As sheet and writes, reporting whether it landed.
    ///
    /// Awaitable, unlike a completion-handler sheet, because closing and
    /// quitting have to know whether the user picked a file or cancelled
    /// before they decide to proceed.
    @discardableResult
    private func saveAs() async -> Bool {
        guard let window else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Untitled.md"
        panel.directoryURL = workspace?.rootURL

        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return false }

        guard let text = await editor.documentText() else {
            presentError(EditorError.unreadable, title: "Could not save \(url.lastPathComponent)")
            return false
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            currentFileURL = url.standardizedFileURL
            editor.markSaved()
            updateTitle()
            WorkspaceStore.saveFile(url)
            workspace?.reload(url.deletingLastPathComponent())
            sidebar.select(url)
            return true
        } catch {
            presentError(error, title: "Could not save \(url.lastPathComponent)")
            return false
        }
    }

    /// Restarts the idle countdown. Typing keeps pushing it back; a pause
    /// lets it fire.
    private func scheduleIdleSave() {
        idleSaveTask?.cancel()
        // 0 means the user asked for no autosave while typing; switching
        // files, leaving the window and quitting still save.
        guard appearance.idleSaveSeconds > 0 else { return }
        idleSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.idleSaveDelay ?? .seconds(2))
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

    // MARK: - Appearance

    @objc func setTheme(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String,
              let theme = Appearance.Theme(rawValue: raw) else { return }
        appearance.theme = theme
        applyAppearance()
    }

    @objc func setFontFamily(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String,
              let family = Appearance.FontFamily(rawValue: raw) else { return }
        appearance.family = family
        applyAppearance()
    }

    @objc func increaseFontSize(_ sender: Any?) { stepFontSize(by: 1) }
    @objc func decreaseFontSize(_ sender: Any?) { stepFontSize(by: -1) }
    @objc func widenMeasure(_ sender: Any?) { stepMeasure(by: 1) }
    @objc func narrowMeasure(_ sender: Any?) { stepMeasure(by: -1) }

    private func stepFontSize(by delta: Int) {
        let sizes = Appearance.fontSizes
        guard let current = sizes.firstIndex(of: appearance.fontSize) else {
            appearance.fontSize = 17
            applyAppearance()
            return
        }
        let next = current + delta
        guard sizes.indices.contains(next) else { return }
        appearance.fontSize = sizes[next]
        applyAppearance()
    }

    private func stepMeasure(by delta: Int) {
        let measures = Appearance.measures
        // Clamp to the nearest step rather than jumping to a default, so a
        // value written by hand still moves in the right direction.
        let current = measures.firstIndex(of: appearance.measure)
            ?? measures.firstIndex { $0 >= appearance.measure }
            ?? 0
        let next = current + delta
        guard measures.indices.contains(next) else { return }
        appearance.measure = measures[next]
        applyAppearance()
    }

    private func applyAppearance() {
        appearance.save()
        editor.applyAppearance(appearance)
        // The sidebar, titlebar and menus are AppKit, not web content: setting
        // CSS variables does nothing for them, which is why the sidebar stayed
        // light when the editor went dark.
        //
        // NSApp, not just the window: a detached NSOpenPanel (runModal, no
        // sheet), a runModal alert, the menu bar, and the Settings window all
        // follow the application's appearance rather than this window's, so
        // without the app-level value they keep following the OS while the
        // editor goes dark.
        NSApp.appearance = appearance.theme.nsAppearance
        window?.appearance = appearance.theme.nsAppearance
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
        if sidebarItem.isCollapsed { sidebarItem.animator().isCollapsed = false }
        sidebarContainer.show(.search)
        sidebarContainer.search.focusField()
    }

    @objc func toggleOutline(_ sender: Any?) {
        // Showing the outline is pointless while the sidebar is hidden.
        if sidebarItem.isCollapsed { sidebarItem.animator().isCollapsed = false }
        sidebarContainer.toggleTab()
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
        // AppKit injects "Show Toolbar" and "Customize Toolbar…" into the View
        // menu whenever a window has a toolbar. Nib's toolbar holds no items
        // and exists only to reserve the titlebar band, so showing it adds a
        // blank second row and nothing else. Disabling is not enough -- the
        // items are removed in makeViewMenuClean() -- but this guards the
        // selectors in case AppKit re-adds them.
        if let action = menuItem.action,
           NSStringFromSelector(action).hasPrefix("toggleToolbarShown")
            || NSStringFromSelector(action).hasPrefix("runToolbarCustomization") {
            return false
        }

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

        case #selector(setTheme(_:)):
            menuItem.state =
                (menuItem.representedObject as? String) == appearance.theme.rawValue ? .on : .off
            return true

        case #selector(setFontFamily(_:)):
            menuItem.state =
                (menuItem.representedObject as? String) == appearance.family.rawValue ? .on : .off
            return true

        case #selector(increaseFontSize(_:)):
            return appearance.fontSize < (Appearance.fontSizes.last ?? 28)

        case #selector(decreaseFontSize(_:)):
            return appearance.fontSize > (Appearance.fontSizes.first ?? 12)

        case #selector(widenMeasure(_:)):
            return appearance.measure < (Appearance.measures.last ?? 80)

        case #selector(narrowMeasure(_:)):
            return appearance.measure > (Appearance.measures.first ?? 32)

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
        // window.title is hidden but still set: it names the window in the
        // Window menu and in Mission Control.
        window?.title = name
        window?.subtitle = ""
        titleLabel.attributedStringValue = Self.titleString(
            name: name,
            state: currentFileURL == nil ? nil : (editor.isDirty ? "Edited" : "Saved")
        )
        window?.representedURL = currentFileURL
    }

    /// "name — state", with the state greyed back so the filename leads.
    private static func titleString(name: String, state: String?) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: name,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        guard let state else { return title }
        title.append(NSAttributedString(
            string: "  —  \(state)",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        ))
        return title
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
            if await saveBeforeLeaving() { self.close() }
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

extension NSToolbarItem.Identifier {
    static let documentTitle = NSToolbarItem.Identifier("NibDocumentTitle")
}

/// Supplies the centred title item.
///
/// The toolbar carries nothing else; it exists so AppKit reserves the titlebar
/// band, and so the title can be centred over the whole window instead of over
/// the editor pane.
extension WorkspaceWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.documentTitle, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .documentTitle, .flexibleSpace]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard identifier == .documentTitle else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = titleLabel
        item.visibilityPriority = .high
        return item
    }
}
