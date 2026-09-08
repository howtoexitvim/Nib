import Foundation
import Testing

@testable import Nib

@Suite("Resolving an asset request to a file")
struct AssetResolutionTests {
    private let base = URL(fileURLWithPath: "/Users/someone/notes")

    private func request(_ path: String) -> URL {
        URL(string: "nib-asset://asset/\(path)")!
    }

    @Test("resolves a path under the document's folder")
    func resolvesRelative() {
        let url = AssetSchemeHandler.fileURL(for: request("doc.assets/a.png"), base: base)
        #expect(url?.path == "/Users/someone/notes/doc.assets/a.png")
    }

    @Test("decodes an escaped name back to the real filename")
    func decodesEscapes() {
        let url = AssetSchemeHandler.fileURL(for: request("my%20notes.assets/shot%201.png"), base: base)
        #expect(url?.path == "/Users/someone/notes/my notes.assets/shot 1.png")
    }

    @Test("refuses to escape the document's folder")
    func rejectsTraversal() {
        // The preview must not become a way to read arbitrary files: a link is
        // page content, and page content is not trusted.
        #expect(AssetSchemeHandler.fileURL(for: request("../../../etc/passwd"), base: base) == nil)
        #expect(AssetSchemeHandler.fileURL(for: request("doc.assets/../../secret"), base: base) == nil)
    }

    @Test("allows a path that only looks like it escapes")
    func allowsInnocentDotDot() {
        // Resolves back inside the folder, so it is fine.
        let url = AssetSchemeHandler.fileURL(for: request("a/../b.png"), base: base)
        #expect(url?.path == "/Users/someone/notes/b.png")
    }

    @Test("has nothing to resolve against without an open document")
    func requiresBase() {
        #expect(AssetSchemeHandler.fileURL(for: request("a.png"), base: nil) == nil)
    }

    @Test("rejects an empty path")
    func rejectsEmpty() {
        #expect(AssetSchemeHandler.fileURL(for: URL(string: "nib-asset://asset/")!, base: base) == nil)
    }

    @Test("a sibling folder with the same prefix is still outside")
    func rejectsPrefixSibling() {
        // "/Users/someone/notes-private" starts with the root's path as a
        // string but is a different folder, so a plain hasPrefix check would
        // wrongly allow it.
        let url = AssetSchemeHandler.fileURL(for: request("../notes-private/x.png"), base: base)
        #expect(url == nil)
    }
}
