import Foundation

/// Which API dialect to speak.
///
/// Deliberately only two. Both are the official, widely-copied protocols; the
/// OpenAI one in particular is what self-hosted servers (vLLM, Ollama, LM
/// Studio, llama.cpp) expose, so supporting it covers local models without any
/// vendor-specific code.
enum Provider: String, CaseIterable {
    case anthropic
    case openai

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI-compatible"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-5"
        case .openai: return "gpt-4o-mini"
        }
    }

    /// Whether a key is required. A local vLLM server usually accepts any value
    /// or none at all, so an empty key must not block the request.
    var requiresKey: Bool {
        self == .anthropic
    }
}

/// Where completions come from. Persisted in UserDefaults; the key itself lives
/// in the Keychain and is never stored here.
struct ProviderSettings {
    var provider: Provider
    var baseURL: String
    var model: String

    static func load() -> ProviderSettings {
        // UserDefaults.standard is fetched per call rather than cached in a
        // static: a shared mutable static is not Sendable under strict
        // concurrency, and this is not a hot path.
        let defaults = UserDefaults.standard
        let provider = Provider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .anthropic
        let base = defaults.string(forKey: "baseURL") ?? ""
        let model = defaults.string(forKey: "model") ?? ""
        return ProviderSettings(
            provider: provider,
            baseURL: base.isEmpty ? provider.defaultBaseURL : base,
            model: model.isEmpty ? provider.defaultModel : model
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(provider.rawValue, forKey: "provider")
        defaults.set(baseURL, forKey: "baseURL")
        defaults.set(model, forKey: "model")
    }

    /// Full endpoint for this provider, tolerating a base URL with or without a
    /// trailing slash or an already-appended path.
    var endpoint: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }

        let path: String
        switch provider {
        case .anthropic:
            path = base.hasSuffix("/v1") ? "/messages" : "/v1/messages"
        case .openai:
            path = base.hasSuffix("/v1") ? "/chat/completions" : "/v1/chat/completions"
        }
        return URL(string: base + path)
    }
}
