import Foundation
import Testing

@testable import Nib

@Suite("Where a clicked link goes")
@MainActor
struct LinkRoutingTests {
    @Test("web links open in the browser")
    func webLinks() {
        for string in ["https://example.com", "http://example.com", "HTTPS://EXAMPLE.COM"] {
            let url = URL(string: string)!
            #expect(EditorViewController.route(url) == .openExternally)
        }
    }

    @Test("mailto opens in the mail client")
    func mailto() {
        #expect(EditorViewController.route(URL(string: "mailto:a@b.com")!) == .openExternally)
    }

    @Test("a link to another note opens in the editor")
    func localFile() {
        let url = URL(fileURLWithPath: "/Users/someone/notes/other.md")
        #expect(EditorViewController.route(url) == .openInEditor)
    }

    @Test("a note cannot launch anything else")
    func refusesOtherSchemes() {
        // Rendered markdown is content, and content should not be able to run
        // a script or hand an arbitrary scheme to the system.
        for string in ["javascript:alert(1)", "data:text/html,<b>x", "ftp://example.com"] {
            let url = URL(string: string)!
            #expect(EditorViewController.route(url) == .ignore)
        }
    }
}
