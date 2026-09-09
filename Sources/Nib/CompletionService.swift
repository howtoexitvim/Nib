import Foundation

/// Asks a model to continue the text at the cursor.
///
/// Runs on the native side so the API key stays in the Keychain, out of the web
/// context. The prompt is tuned for prose: a code-completion model is the wrong
/// tool here -- Copilot ships with `"markdown": false` by default, which is
/// Microsoft conceding the same point.
///
/// Two protocols only: Anthropic's and OpenAI's. The latter is what self-hosted
/// servers such as vLLM expose, so local models need no special handling.
struct CompletionService {
    /// Kept small on purpose. A suggestion longer than a sentence or two stops
    /// being an assist and starts writing the document for you, which is both
    /// slower to read and easier to reject.
    private static let maxTokens = 96

    enum Failure: LocalizedError {
        case missingKey
        case badEndpoint(String)
        case http(Int, String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "No API key set. Use Nib > Settings to add one."
            case let .badEndpoint(url):
                return "Invalid API base URL: \(url)"
            case let .http(status, body):
                return "Completion request failed (\(status)): \(body)"
            case .malformedResponse:
                return "Unexpected response from the completion API."
            }
        }
    }

    private static let systemPrompt = """
    You continue the user's Markdown document at <CURSOR>.

    Rules:
    - Output ONLY the continuation text. No preamble, no quotes, no explanation.
    - Continue mid-sentence if the cursor is mid-sentence. Do not restate what \
    is already written.
    - Write at most one or two sentences, or a single list item.
    - Match the document's existing language, tone, register and formatting. If \
    the document is in Chinese, continue in Chinese.
    - Respect Markdown context: inside a list produce a list item, inside a code \
    block produce code, after a heading produce body text.
    - If the text before the cursor already reads as complete and nothing useful \
    follows, output nothing at all.
    """

    func complete(prefix: String, suffix: String) async throws -> String {
        let settings = ProviderSettings.load()
        // The switch in Settings, honoured at the one place every request
        // passes through -- so turning it off stops the traffic rather than
        // just hiding the fields.
        guard settings.ghostWritingEnabled else { return "" }
        let apiKey = Keychain.readAPIKey() ?? ""
        if settings.provider.requiresKey && apiKey.isEmpty { throw Failure.missingKey }
        guard let endpoint = settings.endpoint else { throw Failure.badEndpoint(settings.baseURL) }

        // Fill-in-the-middle: the text after the cursor matters. Prefix-only
        // completion writes over what the user already has below.
        let userPrompt = """
        <document>
        \(prefix)<CURSOR>\(suffix)
        </document>

        Continue at <CURSOR>.
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        switch settings.provider {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": settings.model,
                "max_tokens": Self.maxTokens,
                "system": Self.systemPrompt,
                "messages": [["role": "user", "content": userPrompt]],
            ]
        case .openai:
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            body = [
                "model": settings.model,
                "max_tokens": Self.maxTokens,
                "messages": [
                    ["role": "system", "content": Self.systemPrompt],
                    ["role": "user", "content": userPrompt],
                ],
                // Reasoning models served by vLLM put their chain of thought in
                // a separate `reasoning` field and leave `content` null, so a
                // short completion budget is spent entirely on thinking and
                // ghost text gets nothing back. Verified against a local
                // Qwen3.8-27B: without this the reply is null; with it the
                // completion arrives directly.
                //
                // OpenAI itself ignores unknown top-level fields, so this is
                // inert against the hosted API.
                "chat_template_kwargs": ["enable_thinking": false],
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw Failure.http(http.statusCode, String(text.prefix(300)))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.malformedResponse
        }
        return Self.sanitize(try Self.extractText(from: json, provider: settings.provider))
    }

    private static func extractText(from json: [String: Any], provider: Provider) throws -> String {
        switch provider {
        case .anthropic:
            guard let content = json["content"] as? [[String: Any]] else {
                throw Failure.malformedResponse
            }
            return content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
        case .openai:
            guard
                let choices = json["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let text = message["content"] as? String
            else { throw Failure.malformedResponse }
            return text
        }
    }

    /// Strips artefacts that would look wrong as inline ghost text.
    ///
    /// Leading newlines are dropped because the widget renders on the current
    /// line; a model that wraps its answer in quotes or a code fence would
    /// otherwise have those characters inserted verbatim on Tab.
    static func sanitize(_ raw: String) -> String {
        var text = raw

        if text.hasPrefix("```") {
            // Drop an opening fence (with optional language) and any closing one.
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
        }

        text = text.replacingOccurrences(of: "<CURSOR>", with: "")
        while text.hasPrefix("\n") { text.removeFirst() }
        // Trailing whitespace would be invisible in the widget but real on accept.
        while let last = text.last, last == " " || last == "\n" { text.removeLast() }

        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }
}
