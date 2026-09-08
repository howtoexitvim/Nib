import AppKit

/// Where completions come from, and the key to reach it.
///
/// The key goes straight to the Keychain -- never UserDefaults, never a plist,
/// never the web context. Everything else is plain preferences.
@MainActor
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    private let providerPopUp = NSPopUpButton()
    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let keyField = NSSecureTextField()
    private let status = NSTextField(labelWithString: "")

    static func show() {
        if shared == nil { shared = SettingsWindowController() }
        shared?.showWindow(nil)
        shared?.window?.center()
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        self.init(window: window)
        window.contentView = makeContentView()
        loadCurrent()
    }

    private func makeContentView() -> NSView {
        let container = NSView()

        providerPopUp.addItems(withTitles: Provider.allCases.map(\.displayName))
        providerPopUp.target = self
        providerPopUp.action = #selector(providerChanged)

        baseURLField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        modelField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        keyField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        keyField.placeholderString = "leave empty for a local server"

        let hint = NSTextField(wrappingLabelWithString:
            "Only the Anthropic and OpenAI protocols are supported. Self-hosted servers "
            + "such as vLLM speak the OpenAI one -- point the base URL at them and leave "
            + "the key empty. The key is stored in your login Keychain.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded

        let grid = NSGridView(views: [
            [label("Provider"), providerPopUp],
            [label("Base URL"), baseURLField],
            [label("Model"), modelField],
            [label("API key"), keyField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        let stack = NSStackView(views: [grid, hint, status, save])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        return container
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func loadCurrent() {
        let settings = ProviderSettings.load()
        providerPopUp.selectItem(at: Provider.allCases.firstIndex(of: settings.provider) ?? 0)
        baseURLField.stringValue = settings.baseURL
        modelField.stringValue = settings.model
        keyField.stringValue = Keychain.readAPIKey() ?? ""
    }

    private var selectedProvider: Provider {
        Provider.allCases[providerPopUp.indexOfSelectedItem]
    }

    /// Switching provider swaps in that provider's defaults, but only when the
    /// fields still hold another provider's defaults -- a URL the user typed is
    /// never overwritten.
    @objc private func providerChanged() {
        let provider = selectedProvider
        let knownDefaults = Provider.allCases.map(\.defaultBaseURL)
        if baseURLField.stringValue.isEmpty || knownDefaults.contains(baseURLField.stringValue) {
            baseURLField.stringValue = provider.defaultBaseURL
        }
        let knownModels = Provider.allCases.map(\.defaultModel)
        if modelField.stringValue.isEmpty || knownModels.contains(modelField.stringValue) {
            modelField.stringValue = provider.defaultModel
        }
    }

    @objc private func save() {
        let provider = selectedProvider
        var settings = ProviderSettings(
            provider: provider,
            baseURL: baseURLField.stringValue.trimmingCharacters(in: .whitespaces),
            model: modelField.stringValue.trimmingCharacters(in: .whitespaces)
        )
        if settings.baseURL.isEmpty { settings.baseURL = provider.defaultBaseURL }
        if settings.model.isEmpty { settings.model = provider.defaultModel }
        settings.save()
        loadFieldsFrom(settings)

        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = Keychain.writeAPIKey(key)

        if !stored {
            status.stringValue = "Could not write the key to the Keychain."
            status.textColor = .systemRed
        } else if provider.requiresKey && key.isEmpty {
            status.stringValue = "Saved, but ghost writing needs a key for \(provider.displayName)."
            status.textColor = .systemOrange
        } else {
            status.stringValue = "Saved."
            status.textColor = .secondaryLabelColor
        }
    }

    private func loadFieldsFrom(_ settings: ProviderSettings) {
        baseURLField.stringValue = settings.baseURL
        modelField.stringValue = settings.model
    }
}
