import Testing
@testable import Nib

/// The parts worth testing are the pure ones: how a model's reply is cleaned up
/// before it becomes ghost text, and how a base URL becomes an endpoint. Both
/// have edge cases that are invisible until they corrupt a document.
@Suite("Completion sanitising")
struct SanitizeTests {
    @Test("passes ordinary prose through untouched")
    func plainText() {
        #expect(CompletionService.sanitize("the rest of the sentence.") == "the rest of the sentence.")
    }

    @Test("strips a fenced code block the model wrapped its answer in")
    func stripsFence() {
        let raw = "```markdown\n- a list item\n```"
        #expect(CompletionService.sanitize(raw) == "- a list item")
    }

    @Test("strips a fence with no language tag")
    func stripsBareFence() {
        #expect(CompletionService.sanitize("```\nhello\n```") == "hello")
    }

    @Test("drops leading newlines, which would break the inline widget")
    func dropsLeadingNewlines() {
        #expect(CompletionService.sanitize("\n\ncontinued") == "continued")
    }

    @Test("drops trailing whitespace, invisible in the widget but real on accept")
    func dropsTrailingSpace() {
        #expect(CompletionService.sanitize("continued  ") == "continued")
        #expect(CompletionService.sanitize("continued\n\n") == "continued")
    }

    @Test("removes a stray cursor marker echoed back by the model")
    func removesCursorMarker() {
        #expect(CompletionService.sanitize("a<CURSOR>b") == "ab")
    }

    @Test("unwraps a fully quoted answer")
    func unwrapsQuotes() {
        #expect(CompletionService.sanitize("\"quoted answer\"") == "quoted answer")
    }

    @Test("leaves quotes that are part of the prose")
    func keepsInnerQuotes() {
        #expect(CompletionService.sanitize("he said \"no\" and left") == "he said \"no\" and left")
    }

    @Test("keeps CJK text intact")
    func keepsCJK() {
        #expect(CompletionService.sanitize("继续写下去。") == "继续写下去。")
    }
}

@Suite("Provider endpoints")
struct EndpointTests {
    private func settings(_ provider: Provider, _ base: String) -> ProviderSettings {
        ProviderSettings(provider: provider, baseURL: base, model: "m")
    }

    @Test("builds the Anthropic messages endpoint")
    func anthropic() {
        let url = settings(.anthropic, "https://api.anthropic.com").endpoint
        #expect(url?.absoluteString == "https://api.anthropic.com/v1/messages")
    }

    @Test("builds the OpenAI chat endpoint")
    func openai() {
        let url = settings(.openai, "https://api.openai.com").endpoint
        #expect(url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test("tolerates a trailing slash")
    func trailingSlash() {
        let url = settings(.openai, "https://api.openai.com/").endpoint
        #expect(url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test("does not double up an already-present /v1")
    func existingV1() {
        // vLLM is usually pointed at as http://host:8000/v1, and appending
        // another /v1 would 404.
        let url = settings(.openai, "http://localhost:8000/v1").endpoint
        #expect(url?.absoluteString == "http://localhost:8000/v1/chat/completions")
    }

    @Test("works for a self-hosted server on a port")
    func selfHosted() {
        let url = settings(.openai, "http://10.0.0.5:8000").endpoint
        #expect(url?.absoluteString == "http://10.0.0.5:8000/v1/chat/completions")
    }

    @Test("only Anthropic demands a key; local servers often have none")
    func keyRequirement() {
        #expect(Provider.anthropic.requiresKey)
        #expect(!Provider.openai.requiresKey)
    }
}
