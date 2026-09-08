import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MenuBuilder.build()

        // Paths on the command line, so `Nib notes.md` works from a shell.
        // application(_:open:) only covers Finder and `open`, not argv.
        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if paths.isEmpty {
            DocumentWindowController.newDocument()
        } else {
            for path in paths {
                DocumentWindowController.open(url: URL(fileURLWithPath: path))
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { DocumentWindowController.open(url: $0) }
    }

    // MARK: - Menu actions routed to the app

    @objc func newDocument(_ sender: Any?) {
        DocumentWindowController.newDocument()
    }

    @objc func openDocument(_ sender: Any?) {
        DocumentWindowController.openWithPanel()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.show()
    }
}
