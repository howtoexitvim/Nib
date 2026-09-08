import Foundation

/// One entry in the workspace tree.
///
/// A value type with the visibility and ordering rules as static functions, so
/// the parts that decide what a user sees are testable without touching disk.
struct FileNode: Identifiable, Hashable {
    /// Always standardized, so two paths to the same file compare equal.
    let url: URL
    let isDirectory: Bool
    /// nil means "a directory whose children have not been read yet"; an empty
    /// array means a directory that is genuinely empty. Files are always nil.
    var children: [FileNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool, children: [FileNode]? = nil) {
        self.url = url.standardizedFileURL
        self.isDirectory = isDirectory
        self.children = children
    }

    /// The file types Nib edits.
    static let markdownExtensions: Set<String> = ["md", "markdown"]

    /// Whether an entry belongs in the sidebar.
    ///
    /// Hides dotfiles and `*.assets` directories: the latter hold pasted images
    /// and are an implementation detail of the document beside them, so showing
    /// them would clutter the tree with folders nobody opens by hand.
    static func isVisible(name: String, isDirectory: Bool) -> Bool {
        if name.hasPrefix(".") { return false }
        if isDirectory { return !name.hasSuffix(".assets") }
        return markdownExtensions.contains(
            (name as NSString).pathExtension.lowercased()
        )
    }

    /// Directories first, then by name.
    ///
    /// `localizedStandard` so `2.md` sorts before `10.md`, which plain string
    /// ordering gets backwards.
    static func sort(_ nodes: [FileNode]) -> [FileNode] {
        nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
