import Foundation
import Testing

@testable import Nib

@Suite("Searching a folder")
struct FileSearchTests {
    private func makeFolder() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nib-search-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("notes.assets"), withIntermediateDirectories: true)

        try "# Alpha\n\nthe needle is here\n".write(
            to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "# Beta\n\nnothing to see\n".write(
            to: root.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "# Deep\n\nanother needle line\n".write(
            to: root.appendingPathComponent("sub/c.md"), atomically: true, encoding: .utf8)
        // Must be skipped: not markdown, and inside an assets folder.
        try "needle".write(
            to: root.appendingPathComponent("image.txt"), atomically: true, encoding: .utf8)
        try "needle".write(
            to: root.appendingPathComponent("notes.assets/caption.md"), atomically: true, encoding: .utf8)
        return root
    }

    private func collect(_ query: String, in root: URL) async -> [SearchHit] {
        var hits: [SearchHit] = []
        let service = FileSearchService()
        for await hit in await service.search(query, in: root) { hits.append(hit) }
        return hits.sorted { $0.id < $1.id }
    }

    @Test("finds matches across nested folders")
    func findsAcrossFolders() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let hits = await collect("needle", in: root)
        let names = hits.map { $0.url.lastPathComponent }.sorted()
        #expect(names == ["a.md", "c.md"])
    }

    @Test("reports one-based line numbers, as editors count them")
    func reportsLineNumbers() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let hits = await collect("needle", in: root)
        let a = try #require(hits.first { $0.url.lastPathComponent == "a.md" })
        #expect(a.line == 3)
        #expect(a.text == "the needle is here")
    }

    @Test("skips assets folders and non-markdown files")
    func skipsNonProse() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let hits = await collect("needle", in: root)
        // image.txt and notes.assets/caption.md both contain the word.
        #expect(!hits.contains { $0.url.lastPathComponent == "image.txt" })
        #expect(!hits.contains { $0.url.path.contains(".assets") })
    }

    @Test("matches regardless of case")
    func caseInsensitive() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await collect("NEEDLE", in: root).count == 2)
    }

    @Test("an empty query searches for nothing")
    func emptyQuery() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await collect("   ", in: root).isEmpty)
    }

    @Test("a query that matches nothing returns nothing")
    func noMatches() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await collect("absent", in: root).isEmpty)
    }
}

@Suite("Which queries are worth searching for")
struct SearchableQueryTests {
    @Test("two Latin characters is the minimum")
    func latinMinimum() {
        #expect(!SearchViewController.isSearchable("a"))
        #expect(SearchViewController.isSearchable("ab"))
    }

    @Test("one CJK character is a whole word")
    func singleIdeograph() {
        // Requiring two would make a single-character search silently do
        // nothing, which reads as "Chinese search is broken".
        #expect(SearchViewController.isSearchable("搜"))
        #expect(SearchViewController.isSearchable("猫"))
        #expect(SearchViewController.isSearchable("あ"))
        #expect(SearchViewController.isSearchable("한"))
    }

    @Test("empty or whitespace searches for nothing")
    func emptyQuery() {
        #expect(!SearchViewController.isSearchable(""))
        #expect(!SearchViewController.isSearchable("   "))
    }

    @Test("a single character that is not ideographic still needs a second")
    func singleLatinRejected() {
        #expect(!SearchViewController.isSearchable("x"))
        #expect(!SearchViewController.isSearchable("1"))
        #expect(!SearchViewController.isSearchable("#"))
    }

    @Test("whitespace around a single ideograph is trimmed")
    func trimsAroundIdeograph() {
        #expect(SearchViewController.isSearchable("  搜  "))
    }
}
