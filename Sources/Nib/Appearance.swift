import AppKit
import Foundation

/// Theme and typography, as the user set them.
///
/// Stored in UserDefaults and applied as CSS custom properties, which the
/// editor theme and the preview stylesheet already read. That is why there are
/// no new CodeMirror compartments here: one setProperty reconfigures both
/// modes at once, and three compartments would be complexity bought for
/// nothing.
struct Appearance: Equatable {
    enum Theme: String, CaseIterable {
        case system, light, dark

        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        /// What AppKit needs for the window chrome. The sidebar, titlebar and
        /// menus are not web content, so CSS variables do nothing for them.
        /// nil means "follow the system", which an unset window already does.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Serif for prose, sans for a more interface-like feel, mono for drafts.
    enum FontFamily: String, CaseIterable {
        case serif, sans, mono

        var label: String {
            switch self {
            case .serif: return "Serif"
            case .sans: return "Sans Serif"
            case .mono: return "Monospace"
            }
        }

        /// The CSS variable the editor already uses for its font stack.
        var cssValue: String {
            switch self {
            case .serif: return "var(--nib-serif)"
            case .sans: return "var(--nib-sans)"
            case .mono: return "var(--nib-mono)"
            }
        }
    }

    /// The window's background, matching the page's --nib-bg exactly.
    ///
    /// `.textBackgroundColor` is close but not equal (#FFFFFF / #1E1E1E against
    /// the page's #fdfdfc / #1e1e1e), so the native frame and the web content
    /// met at a visible seam while the page was still loading or during a
    /// resize. Resolved via `bestMatch` rather than a name switch, so the
    /// accessibility high-contrast appearances map correctly too.
    nonisolated static let paper = NSColor(name: "nibPaper") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x1e / 255, green: 0x1e / 255, blue: 0x1e / 255, alpha: 1)
            : NSColor(srgbRed: 0xfd / 255, green: 0xfd / 255, blue: 0xfc / 255, alpha: 1)
    }

    var theme: Theme = .system
    var family: FontFamily = .serif
    var fontSize: Int = 17
    /// Line length in rem. Prose is unreadable when a line runs the full width
    /// of a wide window, which is why this is a setting rather than 100%.
    var measure: Int = 46

    static let fontSizes = Array(stride(from: 12, through: 28, by: 1))
    static let measures = [32, 38, 46, 54, 64, 80]

    // MARK: - Persistence

    private enum Key {
        static let theme = "appearanceTheme"
        static let family = "appearanceFontFamily"
        static let fontSize = "appearanceFontSize"
        static let measure = "appearanceMeasure"
    }

    static func load(from defaults: UserDefaults = .standard) -> Appearance {
        var appearance = Appearance()
        if let raw = defaults.string(forKey: Key.theme), let theme = Theme(rawValue: raw) {
            appearance.theme = theme
        }
        if let raw = defaults.string(forKey: Key.family), let family = FontFamily(rawValue: raw) {
            appearance.family = family
        }
        // A zero means "never set", not "size zero".
        let size = defaults.integer(forKey: Key.fontSize)
        if size > 0 { appearance.fontSize = size }
        let measure = defaults.integer(forKey: Key.measure)
        if measure > 0 { appearance.measure = measure }
        return appearance
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(theme.rawValue, forKey: Key.theme)
        defaults.set(family.rawValue, forKey: Key.family)
        defaults.set(fontSize, forKey: Key.fontSize)
        defaults.set(measure, forKey: Key.measure)
    }

    /// What the web layer needs, as a JSON object.
    var payload: [String: Any] {
        [
            "theme": theme.rawValue,
            "fontFamily": family.cssValue,
            "fontSize": "\(fontSize)px",
            "measure": "\(measure)rem",
        ]
    }
}
