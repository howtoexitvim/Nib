import AppKit

/// Search across the workspace, as the sidebar's third tab.
///
/// Results stream in as the walk finds them rather than appearing all at once,
/// so a large folder shows its first hits immediately.
@MainActor
final class SearchViewController: NSViewController {
    private let field = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")

    private let service = FileSearchService()
    private var hits: [SearchHit] = []
    /// The running search, cancelled when a new one starts.
    private var searchTask: Task<Void, Never>?

    /// A result was chosen: open that file at that line.
    var onSelect: ((SearchHit) -> Void)?
    /// Where to search. Nil when no folder is open.
    var rootURL: (() -> URL?)?

    override func loadView() {
        field.placeholderString = "Search in folder"
        field.sendsSearchStringImmediately = false
        // Fires as you type; the debounce below keeps that affordable.
        field.sendsWholeSearchString = false
        field.target = self
        field.action = #selector(queryChanged)
        field.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.rowSizeStyle = .default
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hit"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(field)
        root.addSubview(statusLabel)
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),

            statusLabel.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    /// Puts the cursor in the field, for the menu command.
    func focusField() {
        view.window?.makeFirstResponder(field)
    }

    @objc private func queryChanged() {
        let query = field.stringValue
        searchTask?.cancel()
        hits = []
        tableView.reloadData()

        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            // One character matches nearly everything; waiting for two keeps
            // the first keystroke from walking the whole folder.
            statusLabel.stringValue = ""
            return
        }
        guard let root = rootURL?() else {
            statusLabel.stringValue = "No folder is open."
            return
        }

        statusLabel.stringValue = "Searching…"
        searchTask = Task { [weak self] in
            // Debounce: another keystroke within this window replaces the
            // search before any file is read.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }

            for await hit in await self.service.search(query, in: root) {
                if Task.isCancelled { return }
                self.hits.append(hit)
                // Reloading per hit is fine at this scale and keeps results
                // appearing as they are found.
                self.tableView.reloadData()
                self.updateStatus(done: false)
            }
            guard !Task.isCancelled else { return }
            self.updateStatus(done: true)
        }
    }

    private func updateStatus(done: Bool) {
        if hits.isEmpty {
            statusLabel.stringValue = done ? "No matches." : "Searching…"
            return
        }
        let capped = hits.count >= FileSearchService.maximumHits
        let count = "\(hits.count)\(capped ? "+" : "") match\(hits.count == 1 ? "" : "es")"
        statusLabel.stringValue = done ? count : "\(count)…"
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard hits.indices.contains(row) else { return }
        onSelect?(hits[row])
    }
}

extension SearchViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { hits.count }
}

extension SearchViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let hit = hits[row]
        let identifier = NSUserInterfaceItemIdentifier("row")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? Self.makeCell(identifier: identifier)

        // Filename and line above, the matching text below, so a result is
        // identifiable without opening it.
        let name = (hit.url.lastPathComponent as NSString).deletingPathExtension
        let title = NSMutableAttributedString(
            string: "\(name):\(hit.line)\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        title.append(NSAttributedString(
            string: String(hit.text.prefix(120)),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        cell.textField?.attributedStringValue = title
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 38 }

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingTail
        text.maximumNumberOfLines = 2
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
