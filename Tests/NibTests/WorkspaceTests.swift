import Foundation
import Testing
@testable import Nib

/// What the sidebar shows, and in what order. These rules decide what the user
/// sees, and they are pure, so they are worth pinning precisely.
@Suite("Sidebar visibility")
struct FileNodeVisibilityTests {
    @Test("shows markdown files")
    func showsMarkdown() {
        #expect(FileNode.isVisible(name: "notes.md", isDirectory: false))
        #expect(FileNode.isVisible(name: "notes.markdown", isDirectory: false))
        #expect(FileNode.isVisible(name: "NOTES.MD", isDirectory: false))
    }

    @Test("hides everything that is not markdown")
    func hidesOtherFiles() {
        #expect(!FileNode.isVisible(name: "image.png", isDirectory: false))
        #expect(!FileNode.isVisible(name: "notes.txt", isDirectory: false))
        #expect(!FileNode.isVisible(name: "README", isDirectory: false))
    }

    @Test("hides dotfiles and dot-directories")
    func hidesDotfiles() {
        #expect(!FileNode.isVisible(name: ".DS_Store", isDirectory: false))
        #expect(!FileNode.isVisible(name: ".git", isDirectory: true))
        #expect(!FileNode.isVisible(name: ".nib", isDirectory: true))
    }

    @Test("hides the assets folders that hold pasted images")
    func hidesAssetsDirectories() {
        // These belong to the document beside them; showing them would fill the
        // tree with folders nobody opens by hand.
        #expect(!FileNode.isVisible(name: "notes.assets", isDirectory: true))
        #expect(FileNode.isVisible(name: "assets", isDirectory: true))
    }

    @Test("shows ordinary directories")
    func showsDirectories() {
        #expect(FileNode.isVisible(name: "Projects", isDirectory: true))
    }
}

@Suite("Sidebar ordering")
struct FileNodeSortTests {
    private func node(_ name: String, dir: Bool = false) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/w/\(name)"), isDirectory: dir)
    }

    @Test("directories come before files")
    func directoriesFirst() {
        let sorted = FileNode.sort([node("a.md"), node("Zed", dir: true)])
        #expect(sorted.map(\.name) == ["Zed", "a.md"])
    }

    @Test("numbers sort naturally, not lexically")
    func naturalNumberOrder() {
        // Plain string ordering puts "10" before "2", which reads as a bug.
        let sorted = FileNode.sort([node("10.md"), node("2.md"), node("1.md")])
        #expect(sorted.map(\.name) == ["1.md", "2.md", "10.md"])
    }

    @Test("names sort case-insensitively")
    func caseInsensitive() {
        let sorted = FileNode.sort([node("banana.md"), node("Apple.md")])
        #expect(sorted.map(\.name) == ["Apple.md", "banana.md"])
    }
}

@Suite("Document paths")
struct WorkspacePathTests {
    @Test("images live in <name>.assets beside the document")
    func assetsDirectory() {
        let doc = URL(fileURLWithPath: "/notes/plan.md")
        #expect(Workspace.assetsDirectory(for: doc).path == "/notes/plan.assets")
    }

    @Test("only the last extension is replaced")
    func assetsDirectoryWithDots() {
        let doc = URL(fileURLWithPath: "/notes/2026.09.plan.md")
        #expect(Workspace.assetsDirectory(for: doc).path == "/notes/2026.09.plan.assets")
    }

    @Test("a document with no extension still gets an assets folder")
    func assetsDirectoryNoExtension() {
        let doc = URL(fileURLWithPath: "/notes/README")
        #expect(Workspace.assetsDirectory(for: doc).path == "/notes/README.assets")
    }

    @Test("paths with spaces are preserved")
    func assetsDirectorySpaces() {
        let doc = URL(fileURLWithPath: "/my notes/todo list.md")
        #expect(Workspace.assetsDirectory(for: doc).path == "/my notes/todo list.assets")
    }
}

@Suite("Name validation")
struct WorkspaceNameTests {
    @Test("rejects names that would escape the folder or break the filesystem")
    func rejectsBadNames() {
        #expect(!Workspace.isValidName(""))
        #expect(!Workspace.isValidName("   "))
        #expect(!Workspace.isValidName("."))
        #expect(!Workspace.isValidName(".."))
        #expect(!Workspace.isValidName("a/b"))
        #expect(!Workspace.isValidName("a:b"))
    }

    @Test("accepts ordinary names, including CJK")
    func acceptsGoodNames() {
        #expect(Workspace.isValidName("notes"))
        #expect(Workspace.isValidName("2026 plan.md"))
        #expect(Workspace.isValidName("读书笔记"))
    }

    @Test("adds .md unless the name already has a markdown extension")
    func addsExtension() {
        #expect(Workspace.markdownFilename(from: "notes") == "notes.md")
        #expect(Workspace.markdownFilename(from: "notes.md") == "notes.md")
        #expect(Workspace.markdownFilename(from: "notes.markdown") == "notes.markdown")
        // A non-markdown extension is part of the name, not a replacement.
        #expect(Workspace.markdownFilename(from: "notes.txt") == "notes.txt.md")
    }

    @Test("finds the first free name when one is taken")
    func disambiguates() {
        let taken: Set<String> = ["/w/Untitled.md", "/w/Untitled 2.md"]
        let url = Workspace.uniqueURL(
            base: "Untitled",
            extension: "md",
            in: URL(fileURLWithPath: "/w")
        ) { taken.contains($0.path) }
        #expect(url.lastPathComponent == "Untitled 3.md")
    }

    @Test("uses the plain name when nothing collides")
    func noCollision() {
        let url = Workspace.uniqueURL(
            base: "Fresh",
            extension: "md",
            in: URL(fileURLWithPath: "/w")
        ) { _ in false }
        #expect(url.lastPathComponent == "Fresh.md")
    }
}

/// One test that does touch the filesystem, because the interaction between
/// filtering, sorting and lazy loading is the thing most likely to be subtly
/// wrong, and it cannot be seen from the pure functions alone.
@Suite("Reading a real folder")
@MainActor
struct WorkspaceTreeTests {
    private func makeFixture() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nib-test-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("notes.assets"), withIntermediateDirectories: true)
        for name in ["1.md", "10.md", "2.md", "notes.md", "image.png", ".hidden"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try Data().write(to: root.appendingPathComponent("Sub/deep.md"))
        return root
    }

    @Test("lists only markdown and real folders, in natural order")
    func listsVisibleEntries() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = Workspace(rootURL: root)
        let names = (workspace.root.children ?? []).map(\.name)

        // Sub first (directories lead), then natural numeric order. No .hidden,
        // no image.png, and notes.assets is not shown as a folder.
        #expect(names == ["Sub", "1.md", "2.md", "10.md", "notes.md"])
    }

    @Test("a folder's children are read only when asked for")
    func loadsChildrenLazily() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = Workspace(rootURL: root)
        let sub = try #require((workspace.root.children ?? []).first { $0.name == "Sub" })

        // A full walk of a real notes folder measured 0.8s, so the root scan
        // must stop at one level.
        #expect(sub.children == nil)
        #expect(workspace.children(of: sub).map(\.name) == ["deep.md"])
    }

    @Test("renaming a document takes its images with it")
    func renameMovesAssets() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try Data().write(to: root.appendingPathComponent("notes.assets/pic.png"))

        let workspace = Workspace(rootURL: root)
        let renamed = try workspace.rename(root.appendingPathComponent("notes.md"), to: "journal")

        #expect(renamed.lastPathComponent == "journal.md")
        // Leaving the assets behind would break every image link in the file.
        #expect(fm.fileExists(atPath: root.appendingPathComponent("journal.assets/pic.png").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("notes.assets").path))
    }
}
