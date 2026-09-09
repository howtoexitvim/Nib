import Foundation
import Testing

@testable import Nib

@Suite("Appearance settings")
struct AppearanceTests {
    /// A defaults domain of its own, so the tests cannot disturb real settings.
    private func makeDefaults() -> UserDefaults {
        let suite = "nib-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("starts on the system theme at a readable size")
    func defaults() {
        let appearance = Appearance()
        #expect(appearance.theme == .system)
        #expect(appearance.family == .serif)
        #expect(appearance.fontSize == 17)
    }

    @Test("survives a round trip through defaults")
    func roundTrip() {
        let defaults = makeDefaults()
        var saved = Appearance()
        saved.theme = .dark
        saved.family = .mono
        saved.fontSize = 21
        saved.measure = 64
        saved.save(to: defaults)

        #expect(Appearance.load(from: defaults) == saved)
    }

    @Test("falls back to the defaults when nothing was ever saved")
    func loadsEmpty() {
        #expect(Appearance.load(from: makeDefaults()) == Appearance())
    }

    @Test("ignores a stored value that is no longer a valid choice")
    func ignoresUnknown() {
        let defaults = makeDefaults()
        defaults.set("solarized", forKey: "appearanceTheme")
        // A theme removed in a later version must not leave the app unstyled.
        #expect(Appearance.load(from: defaults).theme == .system)
    }

    @Test("treats a missing size as unset rather than as zero")
    func zeroIsNotASize() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "appearanceFontSize")
        #expect(Appearance.load(from: defaults).fontSize == 17)
    }

    @Test("hands the web layer CSS-ready values")
    func payloadIsCSS() {
        var appearance = Appearance()
        appearance.family = .sans
        appearance.fontSize = 19
        appearance.measure = 54

        let payload = appearance.payload
        #expect(payload["fontFamily"] as? String == "var(--nib-sans)")
        // Units included: the page assigns these straight to a CSS property.
        #expect(payload["fontSize"] as? String == "19px")
        #expect(payload["measure"] as? String == "54rem")
    }

    @Test("the window chrome follows the system unless told otherwise")
    func systemThemeLeavesChromeAlone() {
        // The sidebar and titlebar are AppKit, not web content, so the theme
        // has to reach them separately -- nil is what "follow the system"
        // means to a window.
        #expect(Appearance.Theme.system.nsAppearance == nil)
        #expect(Appearance.Theme.dark.nsAppearance?.name == .darkAqua)
        #expect(Appearance.Theme.light.nsAppearance?.name == .aqua)
    }
}

@Suite("Autosave preference")
struct AutosaveSettingTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "nib-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("defaults to two seconds")
    func defaultDelay() {
        #expect(Appearance().idleSaveSeconds == 2)
    }

    @Test("zero is a real choice, not an unset value")
    func zeroMeansOff() {
        // Every other numeric setting treats 0 as "never set". This one does
        // not: 0 means "do not save while I am typing".
        let defaults = makeDefaults()
        defaults.set(0, forKey: "autosaveIdleSeconds")
        #expect(Appearance.load(from: defaults).idleSaveSeconds == 0)
    }

    @Test("a value that is not on offer is ignored")
    func rejectsUnknownDelay() {
        let defaults = makeDefaults()
        defaults.set(37, forKey: "autosaveIdleSeconds")
        #expect(Appearance.load(from: defaults).idleSaveSeconds == 2)
    }

    @Test("survives a round trip")
    func roundTrip() {
        let defaults = makeDefaults()
        var saved = Appearance()
        saved.idleSaveSeconds = 5
        saved.save(to: defaults)
        #expect(Appearance.load(from: defaults).idleSaveSeconds == 5)
    }
}

@Suite("Ghost writing switch")
struct GhostWritingToggleTests {
    @Test("on by default")
    func defaultsOn() {
        // The memberwise default is what a new install gets.
        let fresh = ProviderSettings(provider: .anthropic, baseURL: "", model: "")
        #expect(fresh.ghostWritingEnabled)
    }

    @Test("off stays off")
    func canBeTurnedOff() {
        var settings = ProviderSettings(provider: .anthropic, baseURL: "", model: "")
        settings.ghostWritingEnabled = false
        #expect(!settings.ghostWritingEnabled)
    }
}
