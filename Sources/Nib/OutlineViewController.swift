import AppKit

/// One heading in the document.
struct Heading: Hashable {
    let level: Int
    let text: String
    /// Zero-based line, which is what the editor needs to scroll to it.
    let line: Int
}

/// The document's headings, as the sidebar's other tab.
///
/// A table rather than an outline view: headings are a flat list that happens
/// to be indented. Making it hierarchical would mean deciding what to do with
/// a document that jumps from `#` to `###`, which real documents do all the
/// time, for no benefit over indentation.
@MainActor
final class OutlineViewController: NSViewController {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No headings")

    private var headings: [Heading] = []

    /// A heading was clicked; the window controller scrolls the editor.
    var onSelect: ((Heading) -> Void)?

    override func loadView() {
        tableView.headerView = nil
        tableView.rowSizeStyle = .default
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let container = NSView()
        container.addSubview(scrollView)
        container.addSubview(emptyLabel)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
        ])
        view = container
    }

    /// Shows the headings and highlights the one the cursor is inside.
    func show(_ headings: [Heading], active: Int = -1) {
        let changed = headings != self.headings
        self.headings = headings
        emptyLabel.isHidden = !headings.isEmpty
        // Only reload when the structure actually changed: reloading on every
        // cursor move would fight the selection being set right after.
        if changed { tableView.reloadData() }

        guard headings.indices.contains(active) else {
            tableView.deselectAll(nil)
            return
        }
        // Selecting programmatically must not fire the click action, which
        // would scroll the editor back to the heading on every keystroke.
        isSyncing = true
        tableView.selectRowIndexes([active], byExtendingSelection: false)
        tableView.scrollRowToVisible(active)
        isSyncing = false
    }

    /// True while the selection is being set from the editor's cursor.
    private var isSyncing = false

    @objc private func rowClicked() {
        guard !isSyncing else { return }
        let row = tableView.clickedRow
        guard headings.indices.contains(row) else { return }
        onSelect?(headings[row])
    }
}

extension OutlineViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { headings.count }
}

extension OutlineViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let heading = headings[row]
        let identifier = NSUserInterfaceItemIdentifier("row")

        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? Self.makeCell(identifier: identifier)

        cell.textField?.stringValue = heading.text
        // Indentation carries the level; deeper headings also lighten, so the
        // shape of a long document is readable at a glance.
        (cell.textField?.superview as? IndentedCell)?.indent = CGFloat(heading.level - 1) * 12
        cell.textField?.font = heading.level <= 2
            ? .systemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .medium)
            : .systemFont(ofSize: NSFont.smallSystemFontSize)
        cell.textField?.textColor = heading.level <= 2 ? .labelColor : .secondaryLabelColor
        cell.needsLayout = true
        return cell
    }

    /// A cell that indents its label, since a table has no outline column.
    final class IndentedCell: NSTableCellView {
        var indent: CGFloat = 0 {
            didSet { leading?.constant = indent + 6 }
        }
        var leading: NSLayoutConstraint?
    }

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = IndentedCell()
        cell.identifier = identifier

        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingTail
        cell.addSubview(text)
        cell.textField = text

        let leading = text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6)
        cell.leading = leading
        NSLayoutConstraint.activate([
            leading,
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
