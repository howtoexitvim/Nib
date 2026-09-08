import Foundation

/// One line that matched a search.
struct SearchHit: Identifiable, Hashable {
    let url: URL
    /// One-based, as editors count them.
    let line: Int
    let text: String

    var id: String { "\(url.path):\(line)" }
}

/// Searches a folder's Markdown files for a string.
///
/// Grep-like, with no index. An index would have to be built, invalidated and
/// stored somewhere, and a plain walk of a real notes folder measured under a
/// second -- so the complexity buys nothing here.
///
/// An actor because a search runs off the main thread and can be replaced by
/// the next keystroke's search while it is still going.
actor FileSearchService {
    /// Bigger than this is not prose. Reading a 50MB file into memory to look
    /// for a word would stall the search for no plausible gain.
    private static let maximumFileBytes = 2 * 1024 * 1024
    /// Enough to be useful; past this the list is not what you want anyway.
    static let maximumHits = 500

    /// Yields hits as they are found, so results appear while the walk runs.
    ///
    /// The stream ends when the walk finishes or the task is cancelled.
    func search(_ query: String, in root: URL) -> AsyncStream<SearchHit> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                Self.walk(query: query, root: root, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Synchronous, and static: `FileManager`'s enumerator cannot be iterated
    /// from an async context, and the walk already runs on its own task.
    private static func walk(
        query: String,
        root: URL,
        continuation: AsyncStream<SearchHit>.Continuation
    ) {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        var found = 0
        for case let url as URL in walker {
            if Task.isCancelled { return }

            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                // Assets hold images, not prose; descending into them wastes
                // the walk on files that can never match.
                if url.lastPathComponent.hasSuffix(".assets") { walker.skipDescendants() }
                continue
            }
            guard FileNode.markdownExtensions.contains(url.pathExtension.lowercased()),
                  (values?.fileSize ?? 0) <= Self.maximumFileBytes,
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { continue }

            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                guard line.range(of: needle, options: .caseInsensitive) != nil else { continue }
                continuation.yield(SearchHit(
                    url: url,
                    line: index + 1,
                    text: line.trimmingCharacters(in: .whitespaces)
                ))
                found += 1
                if found >= Self.maximumHits { return }
            }
        }
    }
}
