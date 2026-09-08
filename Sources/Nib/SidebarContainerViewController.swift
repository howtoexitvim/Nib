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

        let root = NSView()
        root.addSubview(picker)
        root.addSubview(container)

        NSLayoutConstraint.activate([
            // Pinned to the safe area, not to the top of the view: a sidebar
            // split item draws up behind the titlebar, so anchoring to the
            // view's own top puts this control under the traffic lights. The
            // safe area is what AppKit reserves for them, so it stays correct
            // without hardcoding a titlebar height.
            picker.topAnchor.constraint(
                equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 8
            ),
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

    /// Flips between files and the outline, for the View menu's Outline item.
    func toggleTab() {
        show(tab == .outline ? .files : .outline)
    }
}
