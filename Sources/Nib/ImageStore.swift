import AppKit
import Foundation

/// Writes pasted images next to the document that references them.
///
/// Images go in `<document name>.assets/`, Typora's convention, and links are
/// written relative -- so a folder can be moved, synced or shared and the
/// images still resolve. Absolute paths into a per-user directory, which is
/// Typora's other option, break the moment a file leaves the machine.
enum ImageStore {
    /// A pasted image bigger than this is refused rather than copied into the
    /// notes folder, where it would bloat every future sync.
    static let maximumBytes = 20 * 1024 * 1024

    enum StoreError: LocalizedError {
        case untitledDocument
        case tooLarge
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .untitledDocument:
                return "Save the document before pasting images, so Nib knows where to put them."
            case .tooLarge:
                return "That image is larger than 20 MB."
            case .unsupportedFormat:
                return "That image format is not supported."
            }
        }
    }

    /// An image file type, identified by its own bytes.
    enum Format: String {
        case png, jpg, gif, webp, tiff

        /// The extension written to disk. TIFF is transcoded, so it never
        /// reaches a filename.
        var fileExtension: String { self == .tiff ? "png" : rawValue }
    }

    /// Identifies an image from its leading bytes.
    ///
    /// Sniffed rather than taken from the pasteboard's claimed type: what the
    /// clipboard says and what the bytes are do not always agree, and the
    /// extension has to match the actual content or nothing will render it.
    static func format(of data: Data) -> Format? {
        func matches(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            guard data.count >= offset + signature.count else { return false }
            let start = data.index(data.startIndex, offsetBy: offset)
            return Array(data[start..<data.index(start, offsetBy: signature.count)]) == signature
        }

        if matches([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if matches([0xFF, 0xD8, 0xFF]) { return .jpg }
        if matches([0x47, 0x49, 0x46, 0x38]) { return .gif }
        // WebP is a RIFF container: "RIFF" then four size bytes then "WEBP".
        if matches([0x52, 0x49, 0x46, 0x46]), matches([0x57, 0x45, 0x42, 0x50], at: 8) { return .webp }
        if matches([0x49, 0x49, 0x2A, 0x00]) || matches([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        return nil
    }

    /// A timestamped name, as Typora writes them.
    static func filename(for format: Format, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return "image-\(formatter.string(from: date)).\(format.fileExtension)"
    }

    /// Escapes a filename for use inside a Markdown link.
    ///
    /// Spaces and parentheses would otherwise end the link early, and Markdown
    /// gives no way to escape them inside `(...)`.
    static func markdownPath(directory: String, filename: String) -> String {
        let path = "\(directory)/\(filename)"
        let allowed = CharacterSet(charactersIn: "/-_.~")
            .union(.alphanumerics)
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    /// Writes an image beside `document`, returning the Markdown to insert.
    ///
    /// TIFF is transcoded to PNG: macOS screenshots arrive as TIFF, which
    /// nothing outside Apple's ecosystem renders, so a file written as-is
    /// would show up broken anywhere the notes are read.
    static func save(
        _ data: Data,
        forDocument document: URL?,
        date: Date = Date()
    ) throws -> String {
        guard let document else { throw StoreError.untitledDocument }
        guard data.count <= maximumBytes else { throw StoreError.tooLarge }
        guard let format = format(of: data) else { throw StoreError.unsupportedFormat }

        var bytes = data
        if format == .tiff {
            guard let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:])
            else { throw StoreError.unsupportedFormat }
            bytes = png
        }

        let directory = Workspace.assetsDirectory(for: document)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Two pastes within the same second would otherwise collide, since the
        // name only has second resolution.
        let name = filename(for: format, date: date)
        let base = (name as NSString).deletingPathExtension
        let url = Workspace.uniqueURL(
            base: base,
            extension: format.fileExtension,
            in: directory
        ) { FileManager.default.fileExists(atPath: $0.path) }

        try bytes.write(to: url, options: .atomic)

        let link = markdownPath(
            directory: directory.lastPathComponent,
            filename: url.lastPathComponent
        )
        return "![](\(link))"
    }
}
