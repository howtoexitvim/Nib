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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 290),
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

        // A URL, a model id and a key are all things you check character by
        // character, which is what monospace is for. The size matches the
        // system font rather than shrinking below it.
        for field in [baseURLField, modelField, keyField] {
            field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        }
        baseURLField.placeholderString = "https://api.anthropic.com"
        modelField.placeholderString = "model id"
        keyField.placeholderString = "leave empty for a local server"

        let hint = NSTextField(wrappingLabelWithString:
            "Only the Anthropic and OpenAI protocols are supported. Self-hosted servers "
            + "such as vLLM speak the OpenAI one: point the base URL at them and leave "
            + "the key empty. The key is stored in your login Keychain.")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor

        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        save.controlSize = .large

        // Labels in one column, controls in the next, as every macOS settings
        // pane is laid out. The label column hugs its text so the fields sit
        // beside their labels instead of drifting to the far edge.
        let grid = NSGridView(views: [
            [label("Provider"), providerPopUp],
            [label("Base URL"), baseURLField],
            [label("Model"), modelField],
            [label("API key"), keyField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        // Pin the label column, or the grid splits the width evenly between
        // the two and the labels take more than half the window.
        grid.column(at: 0).width = 76
        grid.translatesAutoresizingMaskIntoConstraints = false

        hint.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        save.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(grid)
        container.addSubview(hint)
        container.addSubview(status)
        container.addSubview(save)

        let margin: CGFloat = 20
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            status.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            status.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            status.trailingAnchor.constraint(lessThanOrEqualTo: save.leadingAnchor, constant: -10),
            status.centerYAnchor.constraint(equalTo: save.centerYAnchor),

            // Bottom trailing, where a confirming button belongs on macOS.
            save.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            save.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -margin),
            save.topAnchor.constraint(greaterThanOrEqualTo: hint.bottomAnchor, constant: 10),
        ])
        return container
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        // Hug the text, so the label column stays as narrow as its longest
        // label and the fields sit beside it rather than drifting away.
        field.setContentHuggingPriority(.defaultHigh, for: .horizontal)
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
