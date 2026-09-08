import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves local images to the preview over `nib-asset://`.
///
/// The preview needs to display files that live anywhere in the user's notes,
/// but `loadFileURL(_:allowingReadAccessTo:)` grants the page read access to
/// the bundle's `web/` directory only -- so relative paths fail on permissions
/// as well as on resolution. Widening that grant to the whole filesystem would
/// hand every script in the page the ability to read any file.
///
/// Instead the page asks for a URL it cannot itself resolve, and Swift reads
/// the bytes. Filesystem access stays on this side, and it keeps working if
/// the app is ever sandboxed.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "nib-asset"

    /// The directory relative paths resolve against: the open document's
    /// folder. Set on every file switch.
    /// Read on the main thread, where WebKit delivers these requests, and
    /// where the value it reads is mutated.
    private let baseDirectory: @MainActor () -> URL?

    init(baseDirectory: @escaping @MainActor () -> URL?) {
        self.baseDirectory = baseDirectory
    }

    enum AssetError: Error { case notFound }

    /// Turns a request URL back into a file path under the document's folder.
    ///
    /// Rejects anything that escapes that folder: the page is only supposed to
    /// reach images the document references, and a `../` in a link should not
    /// turn the preview into a way to read arbitrary files.
    static func fileURL(for request: URL, base: URL?) -> URL? {
        guard let base else { return nil }
        // nib-asset://asset/<percent-encoded relative path>
        let path = request.path.hasPrefix("/") ? String(request.path.dropFirst()) : request.path
        guard !path.isEmpty else { return nil }

        let resolved = base.appendingPathComponent(path).standardizedFileURL
        let root = base.standardizedFileURL
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            return nil
        }
        return resolved
    }

    private static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        // WebKit delivers scheme tasks on the main thread; the task itself is
        // not Sendable, so it is handled here rather than hopped anywhere.
        let base = MainActor.assumeIsolated { baseDirectory() }
        guard let requested = task.request.url,
              let fileURL = Self.fileURL(for: requested, base: base),
              let data = try? Data(contentsOf: fileURL)
        else {
            task.didFailWithError(AssetError.notFound)
            return
        }

        let response = URLResponse(
            url: requested,
            mimeType: Self.mimeType(for: fileURL),
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Reads are synchronous and already complete by the time a stop could
        // arrive, so there is nothing to cancel.
    }
}
