import Foundation

/// A folder of Markdown files and the tree the sidebar renders.
///
/// Owns the folder and nothing else. The current file lives on the window
/// controller: if a workspace knew which file was open it would also need the
/// dirty state, hence the editor, hence the WebView -- and it would stop being
/// a model that can be reasoned about on its own.
@MainActor
final class Workspace {
    let rootURL: URL
    private(set) var root: FileNode

    /// Called after any change to the tree, so the sidebar can reload.
    var onChange: (() -> Void)?

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        self.root = FileNode(url: self.rootURL, isDirectory: true)
        loadChildren(of: self.rootURL)
    }

    // MARK: - Reading the tree

    /// Reads one directory's immediate children.
    ///
    /// Deliberately not recursive: a full walk of a real notes folder measured
    /// 0.8s, which would stall the window on open. Children load when a folder
    /// is expanded instead.
    @discardableResult
    func loadChildren(of directory: URL) -> [FileNode] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory.standardizedFileURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let nodes = FileNode.sort(contents.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard FileNode.isVisible(name: url.lastPathComponent, isDirectory: isDirectory) else {
                return nil
            }
            return FileNode(url: url, isDirectory: isDirectory)
        })

        update(directory.standardizedFileURL, children: nodes)
        return nodes
    }

    /// Re-reads a directory that changed on disk.
    func reload(_ directory: URL) {
        loadChildren(of: directory)
        onChange?()
    }

    /// Children of a directory, reading them the first time they are asked for.
    func children(of node: FileNode) -> [FileNode] {
        if let children = node.children { return children }
        return loadChildren(of: node.url)
    }

    /// Replaces a directory's children in the tree, wherever it sits.
    private func update(_ directory: URL, children: [FileNode]) {
        root = Self.replacing(directory, in: root, with: children)
    }

    private static func replacing(_ target: URL, in node: FileNode, with children: [FileNode]) -> FileNode {
        var node = node
        if node.url == target {
            // Preserve already-loaded grandchildren so expanding a sibling does
            // not collapse the rest of the tree.
            node.children = children.map { child in
                var child = child
                child.children = node.children?.first { $0.url == child.url }?.children
                return child
            }
            return node
        }
        node.children = node.children?.map { replacing(target, in: $0, with: children) }
        return node
    }

    // MARK: - Paths

    /// Where a document's pasted images live: `<name>.assets` beside the file.
    ///
    /// Typora's convention, chosen so a folder stays portable -- move or sync
    /// it and the relative links still resolve.
    nonisolated static func assetsDirectory(for document: URL) -> URL {
        let base = document.deletingPathExtension().lastPathComponent
        return document.deletingLastPathComponent()
            .appendingPathComponent("\(base).assets", isDirectory: true)
    }

    /// Whether a user-supplied name is safe to create or rename to.
    nonisolated static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." { return false }
        return !trimmed.contains("/") && !trimmed.contains(":") && !trimmed.contains("\0")
    }

    /// Adds `.md` unless the name already carries a Markdown extension.
    nonisolated static func markdownFilename(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let ext = (trimmed as NSString).pathExtension.lowercased()
        return FileNode.markdownExtensions.contains(ext) ? trimmed : "\(trimmed).md"
    }

    /// First free name of the form `base.md`, `base 2.md`, `base 3.md`, …
    nonisolated static func uniqueURL(
        base: String,
        extension ext: String,
        in directory: URL,
        exists: (URL) -> Bool
    ) -> URL {
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var candidate = directory.appendingPathComponent("\(base)\(suffix)")
        var counter = 2
        while exists(candidate) {
            candidate = directory.appendingPathComponent("\(base) \(counter)\(suffix)")
            counter += 1
        }
        return candidate
    }

    // MARK: - Mutating the folder

    @discardableResult
    func createFile(named name: String, in directory: URL) throws -> URL {
        guard Self.isValidName(name) else { throw WorkspaceError.invalidName(name) }
        let filename = Self.markdownFilename(from: name)
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        let url = Self.uniqueURL(base: base, extension: ext, in: directory) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        try Data().write(to: url, options: .withoutOverwriting)
        reload(directory)
        return url
    }

    @discardableResult
    func createFolder(named name: String, in directory: URL) throws -> URL {
        guard Self.isValidName(name) else { throw WorkspaceError.invalidName(name) }
        let url = Self.uniqueURL(base: name.trimmingCharacters(in: .whitespaces), extension: "", in: directory) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        reload(directory)
        return url
    }

    @discardableResult
    func rename(_ url: URL, to name: String) throws -> URL {
        guard Self.isValidName(name) else { throw WorkspaceError.invalidName(name) }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let filename = isDirectory ? name.trimmingCharacters(in: .whitespaces) : Self.markdownFilename(from: name)
        let destination = url.deletingLastPathComponent().appendingPathComponent(filename)

        if destination.standardizedFileURL == url.standardizedFileURL { return url }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw WorkspaceError.alreadyExists(filename)
        }
        try FileManager.default.moveItem(at: url, to: destination)

        // A renamed document's images must follow it, or every link breaks.
        if !isDirectory {
            let assets = Self.assetsDirectory(for: url)
            if FileManager.default.fileExists(atPath: assets.path) {
                try? FileManager.default.moveItem(at: assets, to: Self.assetsDirectory(for: destination))
            }
        }
        reload(url.deletingLastPathComponent())
        return destination
    }

    /// Moves an item to the Trash.
    ///
    /// Never `removeItem`: deleting someone's notes irrecoverably from a context
    /// menu is not acceptable, and the Trash also removes the need to interrupt
    /// with a confirmation dialog.
    func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        reload(url.deletingLastPathComponent())
    }
}

enum WorkspaceError: LocalizedError {
    case invalidName(String)
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case let .invalidName(name):
            return "\"\(name)\" is not a usable name."
        case let .alreadyExists(name):
            return "\"\(name)\" already exists in this folder."
        }
    }
}
