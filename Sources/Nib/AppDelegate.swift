import AppKit
import UniformTypeIdentifiers

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

        // Paths on the command line, so `Nib notes/` works from a shell.
        // application(_:open:) only covers Finder and `open`, not argv.
        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if paths.isEmpty {
            WorkspaceWindowController.main().restoreSession()
            WorkspaceWindowController.present()
        } else {
            for path in paths {
                WorkspaceWindowController.open(url: URL(fileURLWithPath: path))
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Quitting must not drop unsaved edits. The write is async, so termination
    /// is deferred until it lands rather than answered immediately.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await WorkspaceWindowController.main().saveNow()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Re-shows the window after it was closed, since there is only ever one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { WorkspaceWindowController.present() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { WorkspaceWindowController.open(url: $0) }
    }

    // MARK: - Menu actions routed to the app

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText,
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        WorkspaceWindowController.open(url: url)
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.show()
    }
}
