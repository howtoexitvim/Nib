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
        main.addItem(viewMenu())
        main.addItem(windowMenu())
        return main
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
        menu.addItem(.separator())
        menu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
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
