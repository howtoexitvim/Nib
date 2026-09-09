import AppKit

/// The sidebar: a Files / Outline switcher over one of two panes.
///
/// Typora's arrangement. Both panes are kept alive rather than rebuilt on each
/// switch, so the file tree's expansion state and the outline's scroll survive
/// flipping back and forth.
@MainActor
final class SidebarContainerViewController: NSViewController {
    enum Tab: Int { case files, outline, search }

    let files = SidebarViewController()
    let outline = OutlineViewController()
    let search = SearchViewController()

    private let picker = NSSegmentedControl()
    private let container = NSView()
    /// The workspace's name, above the tabs -- Typora's "FILES" header, but
    /// carrying the folder name, which is more use than a fixed word.
    private let header = NSTextField(labelWithString: "")

    private(set) var tab: Tab = .files

    override func loadView() {
        picker.segmentStyle = .automatic
        picker.trackingMode = .selectOne
        picker.segmentCount = 3
        picker.setLabel("Files", forSegment: 0)
        picker.setLabel("Outline", forSegment: 1)
        picker.setLabel("Search", forSegment: 2)
        picker.setSelected(true, forSegment: 0)
        picker.target = self
        picker.action = #selector(tabChanged)
        picker.translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false

        header.font = .systemFont(ofSize: 10, weight: .semibold)
        header.textColor = .tertiaryLabelColor
        header.lineBreakMode = .byTruncatingTail
        header.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(header)
        root.addSubview(picker)
        root.addSubview(container)

        NSLayoutConstraint.activate([
            // Plain padding: the window's content now starts below the
            // titlebar, so there are no traffic lights to clear.
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),

            picker.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            picker.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            picker.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),

            container.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 6),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        addChild(files)
        addChild(outline)
        addChild(search)
        show(.files)
    }

    @objc private func tabChanged() {
        show(Tab(rawValue: picker.selectedSegment) ?? .files)
    }

    func show(_ tab: Tab) {
        self.tab = tab
        picker.setSelected(true, forSegment: tab.rawValue)

        let wanted: NSView
        switch tab {
        case .files: wanted = files.view
        case .outline: wanted = outline.view
        case .search: wanted = search.view
        }
        guard wanted.superview !== container else { return }

        container.subviews.forEach { $0.removeFromSuperview() }
        wanted.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wanted)
        NSLayoutConstraint.activate([
            wanted.topAnchor.constraint(equalTo: container.topAnchor),
            wanted.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            wanted.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wanted.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    /// Names the open folder above the tabs.
    func setWorkspaceName(_ name: String?) {
        header.stringValue = (name ?? "FILES").uppercased()
    }

    /// Flips between files and the outline, for the View menu's Outline item.
    func toggleTab() {
        show(tab == .outline ? .files : .outline)
    }
}
