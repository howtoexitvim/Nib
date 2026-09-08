import Foundation
import Testing

@testable import Nib

@Suite("Recognising an image from its bytes")
struct ImageFormatTests {
    private func data(_ bytes: [UInt8]) -> Data { Data(bytes) }

    @Test("recognises the formats a clipboard actually produces")
    func recognisesFormats() {
        #expect(ImageStore.format(of: data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])) == .png)
        #expect(ImageStore.format(of: data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpg)
        #expect(ImageStore.format(of: data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) == .gif)
        #expect(ImageStore.format(of: data([0x49, 0x49, 0x2A, 0x00])) == .tiff)
    }

    @Test("reads WebP past the RIFF size field")
    func recognisesWebP() {
        // "RIFF", four bytes of length, then "WEBP" -- the marker is at offset
        // 8, so a naive prefix check would miss it.
        var bytes: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00]
        bytes += [0x57, 0x45, 0x42, 0x50]
        #expect(ImageStore.format(of: data(bytes)) == .webp)
    }

    @Test("rejects what is not an image")
    func rejectsOther() {
        #expect(ImageStore.format(of: Data("# not an image".utf8)) == nil)
        #expect(ImageStore.format(of: Data()) == nil)
        // Long enough to pass a length check, wrong bytes.
        #expect(ImageStore.format(of: data([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0, 0, 0, 0])) == nil)
    }

    @Test("TIFF is written as PNG, since nothing else renders TIFF")
    func tiffBecomesPNG() {
        #expect(ImageStore.Format.tiff.fileExtension == "png")
        #expect(ImageStore.Format.jpg.fileExtension == "jpg")
    }
}

@Suite("Naming and linking a saved image")
struct ImageNamingTests {
    @Test("names files the way Typora does")
    func timestampedName() {
        let date = Date(timeIntervalSince1970: 1_757_000_000)
        let name = ImageStore.filename(for: .png, date: date)
        #expect(name.hasPrefix("image-"))
        #expect(name.hasSuffix(".png"))
        // image-yyyyMMdd-HHmmss.png
        #expect(name.count == "image-20260904-123456.png".count)
    }

    @Test("percent-encodes what would otherwise break the link")
    func escapesMarkdownPath() {
        // A space or a paren ends a Markdown link early, and there is no way
        // to escape them inside (...).
        let path = ImageStore.markdownPath(directory: "my notes.assets", filename: "image (1).png")
        #expect(!path.contains(" "))
        #expect(!path.contains("("))
        #expect(path.hasPrefix("my%20notes.assets/"))
    }

    @Test("leaves an ordinary name alone")
    func plainPath() {
        #expect(
            ImageStore.markdownPath(directory: "notes.assets", filename: "image-1.png")
                == "notes.assets/image-1.png"
        )
    }
}

@Suite("Writing an image to disk")
struct ImageWritingTests {
    /// The smallest valid PNG: signature, IHDR, IDAT, IEND.
    private var pngBytes: Data {
        Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82,
        ])
    }

    private func makeFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nib-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("writes beside the document and links to it relatively")
    func writesIntoAssets() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = folder.appendingPathComponent("notes.md")

        let markdown = try ImageStore.save(pngBytes, forDocument: document)

        // A relative link, so the folder stays portable.
        #expect(markdown.hasPrefix("![](notes.assets/image-"))
        #expect(markdown.hasSuffix(".png)"))
        let written = try FileManager.default.contentsOfDirectory(
            atPath: folder.appendingPathComponent("notes.assets").path
        )
        #expect(written.count == 1)
    }

    @Test("two pastes in the same second do not collide")
    func disambiguatesCollisions() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = folder.appendingPathComponent("notes.md")
        let sameSecond = Date(timeIntervalSince1970: 1_757_000_000)

        let first = try ImageStore.save(pngBytes, forDocument: document, date: sameSecond)
        let second = try ImageStore.save(pngBytes, forDocument: document, date: sameSecond)

        // The name only has second resolution, so the second one has to be
        // given a different name rather than overwrite the first.
        #expect(first != second)
        let written = try FileManager.default.contentsOfDirectory(
            atPath: folder.appendingPathComponent("notes.assets").path
        )
        #expect(written.count == 2)
    }

    @Test("an unsaved document has nowhere to put images")
    func refusesUntitled() {
        #expect(throws: ImageStore.StoreError.self) {
            _ = try ImageStore.save(pngBytes, forDocument: nil)
        }
    }

    @Test("refuses something that is not an image")
    func refusesNonImage() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: ImageStore.StoreError.self) {
            _ = try ImageStore.save(
                Data("just text".utf8),
                forDocument: folder.appendingPathComponent("notes.md")
            )
        }
    }
}
