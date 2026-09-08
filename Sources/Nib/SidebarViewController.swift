import AppKit

/// The file tree.
///
/// `NSOutlineView` rather than SwiftUI: the app has no SwiftUI anywhere, and
/// introducing it for one pane would drag in a second view lifecycle to reason
/// about for no gain -- an outline view is exactly this control.
///
/// The controller renders and reports; it never opens or writes files itself.
/// Selection travels up to the window controller, which owns the current file.
@MainActor
final class SidebarViewController: NSViewController {
    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()

    private var workspace: Workspace?

    /// A row was chosen. The window controller decides what that means.
    var onSelect: ((URL) -> Void)?

    override func loadView() {
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 14
        outlineView.autoresizesOutlineColumn = false
        outlineView.style = .sourceList
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        // Clears the transparent titlebar, which the split view draws under.
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        view = scrollView
    }

    // MARK: - Contents

    func show(_ workspace: Workspace?) {
        self.workspace = workspace
        workspace?.onChange = { [weak self] in self?.refresh() }
        outlineView.reloadData()
        // A newly opened folder should show its contents, not a single root row.
        if let root = workspace?.root {
            outlineView.expandItem(node(root), expandChildren: false)
        }
    }

    /// Reloads the tree, keeping expansion and selection where they were.
    ///
    /// Nodes are values, so the objects handed to the outline view before a
    /// change are not the ones handed back after it; expansion has to be
    /// restored by URL rather than left to the outline view.
    func refresh() {
        let expanded = expandedURLs()
        let selected = selectedURL()
        rebuildNodes()
        outlineView.reloadData()
        restore(expanded: expanded)
        if let selected { select(selected) }
    }

    /// Selects a file's row, expanding ancestors so it is visible.
    func select(_ url: URL) {
        guard let workspace else { return }
        let target = url.standardizedFileURL

        // Expand every ancestor between the root and the file first, or the row
        // does not exist to be selected.
        var ancestors: [URL] = []
        var current = target.deletingLastPathComponent()
        while current.path.hasPrefix(workspace.rootURL.path), current.path != workspace.rootURL.path {
            ancestors.append(current)
            current = current.deletingLastPathComponent()
        }
        for url in ancestors.reversed() {
            if let box = boxes[url] { outlineView.expandItem(box) }
        }

        guard let box = boxes[target] else { return }
        let row = outlineView.row(forItem: box)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    var selectedFileURL: URL? { selectedURL() }

    /// The row the context menu was opened on, which is not the selected row.
    var clickedFileURL: URL? {
        let row = outlineView.clickedRow
        guard row >= 0, let box = outlineView.item(atRow: row) as? NodeBox else { return nil }
        return box.node.url
    }

    var clickedNodeIsDirectory: Bool {
        let row = outlineView.clickedRow
        guard row >= 0, let box = outlineView.item(atRow: row) as? NodeBox else { return false }
        return box.node.isDirectory
    }

    func attach(menu: NSMenu) {
        outlineView.menu = menu
    }

    // MARK: - Identity

    /// `NSOutlineView` holds its items by object identity, but `FileNode` is a
    /// value type -- so each URL gets one stable box that survives reloads.
    final class NodeBox: NSObject {
        var node: FileNode
        init(_ node: FileNode) { self.node = node }
    }

    private var boxes: [URL: NodeBox] = [:]

    private func node(_ node: FileNode) -> NodeBox {
        if let existing = boxes[node.url] {
            existing.node = node
            return existing
        }
        let box = NodeBox(node)
        boxes[node.url] = box
        return box
    }

    /// Refreshes every box in place from the current tree, and drops boxes for
    /// paths that no longer exist so the map does not grow without bound.
    private func rebuildNodes() {
        guard let root = workspace?.root else {
            boxes.removeAll()
            return
        }
        var live: Set<URL> = []
        func walk(_ node: FileNode) {
            live.insert(node.url)
            _ = self.node(node)
            node.children?.forEach(walk)
        }
        walk(root)
        boxes = boxes.filter { live.contains($0.key) }
    }

    private func expandedURLs() -> Set<URL> {
        var urls: Set<URL> = []
        for row in 0..<outlineView.numberOfRows {
            guard let box = outlineView.item(atRow: row) as? NodeBox else { continue }
            if outlineView.isItemExpanded(box) { urls.insert(box.node.url) }
        }
        return urls
    }

    private func restore(expanded: Set<URL>) {
        // Expanding a row reveals more rows, so the loop has to re-check the
        // count rather than snapshot it.
        var row = 0
        while row < outlineView.numberOfRows {
            if let box = outlineView.item(atRow: row) as? NodeBox, expanded.contains(box.node.url) {
                outlineView.expandItem(box)
            }
            row += 1
        }
    }

    private func selectedURL() -> URL? {
        let row = outlineView.selectedRow
        guard row >= 0, let box = outlineView.item(atRow: row) as? NodeBox else { return nil }
        return box.node.url
    }

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let box = outlineView.item(atRow: row) as? NodeBox else { return }
        if box.node.isDirectory {
            // Match the Finder: a click on a folder opens or closes it.
            if outlineView.isItemExpanded(box) {
                outlineView.collapseItem(box)
            } else {
                outlineView.expandItem(box)
            }
        } else {
            onSelect?(box.node.url)
        }
    }
}

// MARK: - Data source

extension SidebarViewController: NSOutlineViewDataSource {
    private func children(of item: Any?) -> [FileNode] {
        guard let workspace else { return [] }
        guard let box = item as? NodeBox else {
            // The root itself is the single top-level row.
            return [workspace.root]
        }
        return workspace.children(of: box.node)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(children(of: item)[index])
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? NodeBox)?.node.isDirectory ?? false
    }
}

// MARK: - Delegate

extension SidebarViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let box = item as? NodeBox else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("row")

        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? Self.makeCell(identifier: identifier)

        cell.textField?.stringValue = box.node.isDirectory
            ? box.node.name
            : (box.node.name as NSString).deletingPathExtension
        cell.imageView?.image = NSImage(
            systemSymbolName: box.node.isDirectory ? "folder" : "doc.text",
            accessibilityDescription: nil
        )
        cell.imageView?.contentTintColor = .secondaryLabelColor
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        // Reading the folder here rather than in the data source keeps the load
        // on the interaction that asks for it.
        if let box = item as? NodeBox, let workspace {
            _ = workspace.children(of: box.node)
        }
        return true
    }

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingTail
        text.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1)

        cell.addSubview(image)
        cell.addSubview(text)
        cell.imageView = image
        cell.textField = text

        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
