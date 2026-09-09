import AppKit

/// Preferences, in the shape macOS uses: a toolbar of tabs, one pane each.
///
/// Deliberately few knobs. Every setting here is one somebody would actually
/// change; the tuning constants behind ghost writing (debounce, context length,
/// completion length) stay constants, because they interact -- a longer context
/// is slower and dearer -- and a wrong combination degrades the feature in a
/// way that is hard to attribute to a setting.
///
/// The API key goes straight to the Keychain: never UserDefaults, never a
/// plist, never the web context.
/// Resizes the window to whichever pane is showing.
///
/// A plain `NSTabViewController` sizes itself to the tallest pane and keeps
/// that height for all of them, so a one-row General pane would be padded out
/// to the height of the AI pane. Safari and Xcode resize per tab; so does this.
@MainActor
private final class ResizingTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        guard let window = view.window, let pane = item?.viewController?.view else { return }

        pane.layoutSubtreeIfNeeded()
        let size = pane.fittingSize
        // The frame includes the titlebar and the tab toolbar; convert so the
        // *content* ends up the pane's size.
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = window.frame.origin
        // Windows grow downward from the top-left on macOS.
        frame.origin.y += window.frame.height - frame.height
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    // General
    private let idlePopUp = NSPopUpButton()

    // Appearance
    private let themePopUp = NSPopUpButton()
    private let fontPopUp = NSPopUpButton()
    private let sizePopUp = NSPopUpButton()
    private let measurePopUp = NSPopUpButton()

    // AI
    private let ghostToggle = NSSwitch()
    private let providerPopUp = NSPopUpButton()
    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let keyField = NSSecureTextField()
    private let status = NSTextField(labelWithString: "")

    /// Applied live, so a change is visible without reopening anything.
    static var onAppearanceChange: ((Appearance) -> Void)?

    static func show() {
        if shared == nil { shared = SettingsWindowController() }
        shared?.showWindow(nil)
        shared?.window?.center()
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        self.init(window: window)

        let tabs = ResizingTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(makeTab("General", symbol: "gearshape", view: makeGeneralPane()))
        tabs.addTabViewItem(makeTab("Appearance", symbol: "textformat", view: makeAppearancePane()))
        tabs.addTabViewItem(makeTab("AI", symbol: "sparkles", view: makeAIPane()))
        window.contentViewController = tabs

        loadCurrent()
    }

    private func makeTab(_ label: String, symbol: String, view: NSView) -> NSTabViewItem {
        let controller = NSViewController()
        controller.view = view
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    // MARK: - Panes

    private func makeGeneralPane() -> NSView {
        idlePopUp.addItems(withTitles: Appearance.idleDelays.map(Self.idleLabel))
        idlePopUp.target = self
        idlePopUp.action = #selector(appearanceChanged)

        return pane(
            rows: [(label("Autosave"), idlePopUp)],
            hint: "Nib always saves when you switch files, leave the window or quit. "
                + "This is the extra save while you are still typing. A document that "
                + "has never been saved is asked about rather than written silently."
        )
    }

    private func makeAppearancePane() -> NSView {
        themePopUp.addItems(withTitles: Appearance.Theme.allCases.map(\.label))
        fontPopUp.addItems(withTitles: Appearance.FontFamily.allCases.map(\.label))
        sizePopUp.addItems(withTitles: Appearance.fontSizes.map { "\($0) pt" })
        measurePopUp.addItems(withTitles: Appearance.measures.map { "\($0) rem" })

        for popUp in [themePopUp, fontPopUp, sizePopUp, measurePopUp] {
            popUp.target = self
            popUp.action = #selector(appearanceChanged)
        }

        return pane(
            rows: [
                (label("Theme"), themePopUp),
                (label("Font"), fontPopUp),
                (label("Size"), sizePopUp),
                (label("Line width"), measurePopUp),
            ],
            hint: "Applies to the editor and the preview alike. Line width is the "
                + "measure the text column is held to -- prose set across a wide "
                + "window is hard to read."
        )
    }

    private func makeAIPane() -> NSView {
        ghostToggle.target = self
        ghostToggle.action = #selector(ghostToggled)

        providerPopUp.addItems(withTitles: Provider.allCases.map(\.displayName))
        providerPopUp.target = self
        providerPopUp.action = #selector(providerChanged)

        for field in [baseURLField, modelField, keyField] {
            field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        }
        baseURLField.placeholderString = "https://api.anthropic.com"
        modelField.placeholderString = "model id"
        keyField.placeholderString = "leave empty for a local server"

        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded

        return pane(
            rows: [
                (label("Ghost writing"), ghostToggle),
                (label("Provider"), providerPopUp),
                (label("Base URL"), baseURLField),
                (label("Model"), modelField),
                (label("API key"), keyField),
            ],
            hint: "Only the Anthropic and OpenAI protocols are supported. Self-hosted "
                + "servers such as vLLM speak the OpenAI one: point the base URL at "
                + "them and leave the key empty. The key is stored in your login Keychain.",
            footer: (status, save)
        )
    }

    // MARK: - Layout

    /// One pane: a label/control grid, a hint, and an optional footer row.
    ///
    /// The label column is pinned so the controls sit beside their labels
    /// rather than drifting to the far edge, which is what a stretched grid
    /// does.
    private func pane(
        rows: [(NSTextField, NSView)],
        hint: String,
        footer: (NSTextField, NSButton)? = nil
    ) -> NSView {
        let container = NSView()

        let grid = NSGridView(views: rows.map { [$0.0, $0.1] })
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 0).width = 92
        grid.translatesAutoresizingMaskIntoConstraints = false

        // Text fields fill the remaining width; a switch or pop-up stretched
        // across the pane looks broken.
        for (_, control) in rows where control is NSTextField {
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            control.widthAnchor.constraint(equalToConstant: 330).isActive = true
        }

        let hintLabel = NSTextField(wrappingLabelWithString: hint)
        hintLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        // Without a preferred width a wrapping label reports its intrinsic
        // height as if it were one very long line, and the pane -- and so the
        // whole window -- grows to fit that.
        hintLabel.preferredMaxLayoutWidth = 480 - 2 * 20

        container.addSubview(grid)
        container.addSubview(hintLabel)

        let margin: CGFloat = 20
        var constraints: [NSLayoutConstraint] = [
            container.widthAnchor.constraint(equalToConstant: 480),

            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            hintLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            hintLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            hintLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
        ]

        if let (status, button) = footer {
            status.translatesAutoresizingMaskIntoConstraints = false
            button.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(status)
            container.addSubview(button)
            constraints += [
                button.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 14),
                button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
                button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -margin),
                status.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
                status.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -10),
                status.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ]
        } else {
            constraints.append(
                hintLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -margin)
            )
        }

        NSLayoutConstraint.activate(constraints)
        return container
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        field.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return field
    }

    private static func idleLabel(_ seconds: Int) -> String {
        seconds == 0 ? "Only when leaving" : "After \(seconds) second\(seconds == 1 ? "" : "s")"
    }

    // MARK: - State

    private func loadCurrent() {
        let settings = ProviderSettings.load()
        providerPopUp.selectItem(at: Provider.allCases.firstIndex(of: settings.provider) ?? 0)
        baseURLField.stringValue = settings.baseURL
        modelField.stringValue = settings.model
        keyField.stringValue = Keychain.readAPIKey() ?? ""
        ghostToggle.state = settings.ghostWritingEnabled ? .on : .off
        updateAIEnablement()

        let appearance = Appearance.load()
        themePopUp.selectItem(at: Appearance.Theme.allCases.firstIndex(of: appearance.theme) ?? 0)
        fontPopUp.selectItem(at: Appearance.FontFamily.allCases.firstIndex(of: appearance.family) ?? 0)
        sizePopUp.selectItem(at: Appearance.fontSizes.firstIndex(of: appearance.fontSize) ?? 0)
        measurePopUp.selectItem(at: Appearance.measures.firstIndex(of: appearance.measure) ?? 0)
        idlePopUp.selectItem(at: Appearance.idleDelays.firstIndex(of: appearance.idleSaveSeconds) ?? 2)
    }

    /// The provider fields say nothing while ghost writing is off.
    private func updateAIEnablement() {
        let on = ghostToggle.state == .on
        [providerPopUp, baseURLField, modelField, keyField].forEach { $0.isEnabled = on }
    }

    private var selectedProvider: Provider {
        Provider.allCases[providerPopUp.indexOfSelectedItem]
    }

    // MARK: - Actions

    /// Appearance and autosave apply immediately; there is nothing to confirm.
    @objc private func appearanceChanged() {
        var appearance = Appearance()
        appearance.theme = Appearance.Theme.allCases[themePopUp.indexOfSelectedItem]
        appearance.family = Appearance.FontFamily.allCases[fontPopUp.indexOfSelectedItem]
        appearance.fontSize = Appearance.fontSizes[sizePopUp.indexOfSelectedItem]
        appearance.measure = Appearance.measures[measurePopUp.indexOfSelectedItem]
        appearance.idleSaveSeconds = Appearance.idleDelays[idlePopUp.indexOfSelectedItem]
        appearance.save()
        Self.onAppearanceChange?(appearance)
    }

    @objc private func ghostToggled() {
        updateAIEnablement()
        var settings = ProviderSettings.load()
        settings.ghostWritingEnabled = ghostToggle.state == .on
        settings.save()
        status.stringValue = settings.ghostWritingEnabled
            ? "Ghost writing is on."
            : "Ghost writing is off; no requests will be made."
        status.textColor = .secondaryLabelColor
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
            model: modelField.stringValue.trimmingCharacters(in: .whitespaces),
            ghostWritingEnabled: ghostToggle.state == .on
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
        } else if settings.ghostWritingEnabled && provider.requiresKey && key.isEmpty {
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
