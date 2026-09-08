import Foundation

/// Remembers the last folder and file across launches.
///
/// Stores security-scoped bookmarks rather than paths. The app is unsandboxed
/// today so a path would work, but a bookmark costs nothing extra now and is
/// the only thing that survives sandboxing later -- and it follows a folder
/// that the user moves or renames, which a path does not.
enum WorkspaceStore {
    private static let folderKey = "lastWorkspaceBookmark"
    private static let fileKey = "lastOpenFileBookmark"

    static func saveFolder(_ url: URL?) { save(url, forKey: folderKey) }
    static func loadFolder() -> URL? { load(forKey: folderKey, requireDirectory: true) }

    static func saveFile(_ url: URL?) { save(url, forKey: fileKey) }
    static func loadFile() -> URL? { load(forKey: fileKey, requireDirectory: false) }

    private static func save(_ url: URL?, forKey key: String) {
        let defaults = UserDefaults.standard
        guard let url else {
            defaults.removeObject(forKey: key)
            return
        }
        let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private static func load(forKey key: String, requireDirectory: Bool) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        // A stale bookmark still resolves; refreshing it keeps the next launch
        // from doing the same work.
        if isStale { save(url, forKey: key) }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue == requireDirectory
        else { return nil }

        return url.standardizedFileURL
    }
}
