import AppKit

/// Builds the menu bar in code.
///
/// Actions are sent to `nil` so they travel the responder chain and land on
/// whichever window is key -- that is what makes Cmd+S act on the front
/// document without any window bookkeeping here.
@MainActor
enum MenuBuilder {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(appMenu())
        main.addItem(fileMenu())
        main.addItem(editMenu())
        main.addItem(formatMenu())
        main.addItem(viewMenu())
        main.addItem(windowMenu())
        return main
    }

    /// Strips the items AppKit injects into the View menu.
    ///
    /// Two families, both unwanted:
    ///
    /// - Toolbar items, added for any window that has a toolbar. Nib's toolbar
    ///   carries no items -- it exists only so the titlebar band is reserved --
    ///   so "Show Toolbar" adds a blank second row and makes the titlebar
    ///   taller for nothing.
    /// - Tab-bar items, added for any window with tabbing enabled. Nib
    ///   deliberately has no tabs: the sidebar is already the navigation
    ///   surface, and a second one would compete with it.
    static func removeInjectedItems(from menu: NSMenu?) {
        guard let view = menu?.items.first(where: { $0.title == "View" })?.submenu else { return }
        let unwanted = [
            "toggleToolbarShown", "runToolbarCustomization",
            "toggleTabBar", "toggleTabOverview",
        ]
        view.items
            .filter { item in
                guard let action = item.action else { return false }
                let name = NSStringFromSelector(action)
                return unwanted.contains { name.hasPrefix($0) }
            }
            .forEach(view.removeItem)

        // Trailing separators left behind by the removals.
        while let last = view.items.first, last.isSeparatorItem {
            view.removeItem(last)
        }
    }

    private static func submenu(_ title: String) -> (NSMenuItem, NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        return (item, menu)
    }

    private static func appMenu() -> NSMenuItem {
        let (item, menu) = submenu("Nib")
        menu.addItem(withTitle: "About Nib", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        menu.addItem(settings)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Hide Nib", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nib", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item
    }

    private static func fileMenu() -> NSMenuItem {
        let (item, menu) = submenu("File")
        menu.addItem(withTitle: "New File", action: #selector(WorkspaceWindowController.newFile(_:)), keyEquivalent: "n")

        let newFolder = NSMenuItem(
            title: "New Folder",
            action: #selector(WorkspaceWindowController.newFolder(_:)),
            keyEquivalent: "n"
        )
        newFolder.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(newFolder)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")

        let openFolder = NSMenuItem(
            title: "Open Folder…",
            action: #selector(WorkspaceWindowController.openFolderWithPanel(_:)),
            keyEquivalent: "o"
        )
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openFolder)

        // NSDocumentController fills and persists this itself; every open and
        // save already calls noteNewRecentDocumentURL.
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.identifier = NSUserInterfaceItemIdentifier("NSRecentDocumentsMenu")
        recent.submenu = recentMenu
        menu.addItem(recent)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save", action: #selector(WorkspaceWindowController.saveDocument(_:)), keyEquivalent: "s")

        let saveAs = NSMenuItem(title: "Save As…", action: #selector(WorkspaceWindowController.saveDocumentAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAs)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Rename…", action: #selector(WorkspaceWindowController.renameItem(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Move to Trash", action: #selector(WorkspaceWindowController.trashItem(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let reveal = NSMenuItem(
            title: "Reveal in Finder",
            action: #selector(WorkspaceWindowController.revealInFinder(_:)),
            keyEquivalent: "r"
        )
        reveal.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(reveal)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return item
    }

    private static func editMenu() -> NSMenuItem {
        let (item, menu) = submenu("Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        // Cmd+F is Find, as it is everywhere else. Full Screen gives up the
        // chord and takes the standard Ctrl+Cmd+F instead.
        // One item: the panel it opens carries its own replace toggle, so a
        // separate "Find and Replace" opened the identical panel.
        menu.addItem(withTitle: "Find", action: #selector(WorkspaceWindowController.performFind(_:)), keyEquivalent: "f")

        let findInFolder = NSMenuItem(
            title: "Find in Folder…",
            action: #selector(WorkspaceWindowController.performFindInFolder(_:)),
            keyEquivalent: "f"
        )
        findInFolder.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(findInFolder)
        return item
    }

    /// Markdown formatting. The commands write the source characters -- there
    /// is no rich-text model to toggle -- so they only apply in source mode.
    private static func formatMenu() -> NSMenuItem {
        let (item, menu) = submenu("Format")
        menu.addItem(withTitle: "Bold", action: #selector(WorkspaceWindowController.formatBold(_:)), keyEquivalent: "b")
        menu.addItem(withTitle: "Italic", action: #selector(WorkspaceWindowController.formatItalic(_:)), keyEquivalent: "i")
        menu.addItem(withTitle: "Code", action: #selector(WorkspaceWindowController.formatCode(_:)), keyEquivalent: "`")
        menu.addItem(withTitle: "Link", action: #selector(WorkspaceWindowController.formatLink(_:)), keyEquivalent: "k")
        menu.addItem(.separator())

        for level in 1...6 {
            let heading = NSMenuItem(
                title: "Heading \(level)",
                action: #selector(WorkspaceWindowController.formatHeading(_:)),
                keyEquivalent: "\(level)"
            )
            // The level travels on the item, so one action serves all six.
            heading.tag = level
            menu.addItem(heading)
        }
        let paragraph = NSMenuItem(
            title: "Paragraph",
            action: #selector(WorkspaceWindowController.formatHeading(_:)),
            keyEquivalent: "0"
        )
        paragraph.tag = 0
        menu.addItem(paragraph)
        return item
    }

    private static func viewMenu() -> NSMenuItem {
        let (item, menu) = submenu("View")

        // This item owns Cmd+/ outright. Binding it here *and* in a web keydown
        // listener fired the toggle twice per press, which read as a phantom
        // third, blank mode.
        menu.addItem(withTitle: "Toggle Preview", action: #selector(WorkspaceWindowController.toggleRenderMode(_:)), keyEquivalent: "/")

        let sidebar = NSMenuItem(
            title: "Toggle Sidebar",
            action: #selector(WorkspaceWindowController.toggleSidebar(_:)),
            keyEquivalent: "s"
        )
        sidebar.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(sidebar)
        let outline = NSMenuItem(
            title: "Outline",
            action: #selector(WorkspaceWindowController.toggleOutline(_:)),
            keyEquivalent: "o"
        )
        outline.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(outline)
        menu.addItem(.separator())
        // Bigger/Smaller Text only. Theme, font and line width now live in
        // Settings > Appearance; duplicating pickers in a menu means two places
        // to keep in step for no gain. Cmd +/- stays because every app has it
        // and reaching for Settings mid-sentence is friction.
        let bigger = NSMenuItem(
            title: "Bigger Text",
            action: #selector(WorkspaceWindowController.increaseFontSize(_:)),
            keyEquivalent: "+"
        )
        menu.addItem(bigger)
        menu.addItem(withTitle: "Smaller Text", action: #selector(WorkspaceWindowController.decreaseFontSize(_:)), keyEquivalent: "-")
        menu.addItem(.separator())

        // Cmd+F went to Find; this is the macOS-standard chord anyway.
        let fullScreen = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(fullScreen)
        return item
    }

    private static func windowMenu() -> NSMenuItem {
        let (item, menu) = submenu("Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = menu
        return item
    }
}
