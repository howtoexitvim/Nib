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
        field.delegate = self
        field.sendsSearchStringImmediately = false
        // Fires as you type; the debounce below keeps that affordable.
        field.sendsWholeSearchString = false
        field.target = self
        field.action = #selector(queryChanged)
        field.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.rowSizeStyle = .default
        // .sourceList, matching the file tree. .inset draws its own opaque
        // background, so this pane became a solid rectangle sitting inside the
        // sidebar's vibrant material -- the tabs above stayed translucent while
        // the list below went flat, in both themes.
        tableView.style = .sourceList
        tableView.backgroundColor = .clear
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

    /// What was searched for, so a result can be highlighted when opened.
    var currentQuery: String { field.stringValue.trimmingCharacters(in: .whitespaces) }

    /// Puts the cursor in the field, for the menu command.
    func focusField() {
        view.window?.makeFirstResponder(field)
    }

    /// Whether a query is worth walking the folder for.
    ///
    /// Two characters for Latin -- one letter matches nearly everything, and
    /// the first keystroke should not scan the whole folder. But one CJK
    /// character is a whole word (搜, 猫, 书), so requiring two there means a
    /// single-character search silently does nothing, which reads as "Chinese
    /// search is broken".
    nonisolated static func isSearchable(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        if trimmed.count >= 2 { return true }
        return trimmed.unicodeScalars.allSatisfy(isIdeographic)
    }

    /// Han, Hiragana, Katakana, Hangul: scripts where one character is a word.
    nonisolated private static func isIdeographic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,   // kana
             0x3400...0x4DBF,   // CJK extension A
             0x4E00...0x9FFF,   // CJK unified
             0xF900...0xFAFF,   // compatibility ideographs
             0xAC00...0xD7AF:   // hangul syllables
            return true
        default:
            return false
        }
    }

    @objc private func queryChanged() {
        let query = field.stringValue
        searchTask?.cancel()
        hits = []
        tableView.reloadData()

        guard Self.isSearchable(query) else {
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

extension SearchViewController: NSSearchFieldDelegate {
    /// Skips searching while an input method is still composing.
    ///
    /// Typing 搜索 with pinyin sends "s", "so", "sou"… as the composition
    /// builds; each is a real edit to the field, so each would kick off a walk
    /// of the whole folder for a string the user never meant to search for.
    /// Waiting until the composition commits also means the first search sees
    /// the Chinese, not the romanisation.
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        let editor = field.currentEditor() as? NSTextView
        if editor?.hasMarkedText() == true { return }
        queryChanged()
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
