import UIKit
import XCTest
@testable import Scowld

/// Request shape and response handling for every chat provider. All HTTP is
/// answered in-process by `StubURLProtocol`; no API key or network is used.
@MainActor
final class LLMProviderTests: XCTestCase {
    private let conversation = [
        ChatMessage(role: .user, content: "Hi"),
        ChatMessage(role: .assistant, content: "[happy] Hello!"),
        ChatMessage(role: .user, content: "What do you see?"),
    ]

    private func stub(_ responder: @escaping (URLRequest) -> StubURLProtocol.Response) {
        StubURLProtocol.install(responder)
        addTeardownBlock { StubURLProtocol.uninstall() }
    }

    private func lastRequest() throws -> StubURLProtocol.Recorded {
        try XCTUnwrap(StubURLProtocol.requests.last, "no request was sent")
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private static let openAIReply = ["choices": [["message": ["role": "assistant", "content": "[happy] Stubbed reply"]]]]

    // MARK: - Gemini

    func testGeminiRequestAndReply() async throws {
        stub { _ in .json(["candidates": [["content": ["parts": [["text": "[happy] Gemini reply"]]]]]]) }
        let reply = try await GeminiProvider(apiKey: "test-key", model: "gemini-2.5-flash")
            .generate(messages: conversation, systemPrompt: "SYSTEM")
        XCTAssertEqual(reply, "[happy] Gemini reply")

        let sent = try lastRequest()
        let url = try XCTUnwrap(sent.request.url)
        XCTAssertEqual(url.host, "generativelanguage.googleapis.com")
        XCTAssertEqual(url.path, "/v1beta/models/gemini-2.5-flash:generateContent")
        XCTAssertNil(url.query, "The API key must not be sent in the URL")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
        XCTAssertEqual(sent.request.httpMethod, "POST")

        let contents = try XCTUnwrap(sent.json["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.compactMap { $0["role"] as? String }, ["user", "model", "user"])
        let system = try XCTUnwrap(sent.json["systemInstruction"] as? [String: Any])
        XCTAssertEqual((system["parts"] as? [[String: String]])?.first?["text"], "SYSTEM")
        let config = try XCTUnwrap(sent.json["generationConfig"] as? [String: Any])
        XCTAssertEqual(config["maxOutputTokens"] as? Int, 8192)
        // Gemini 2.5 still takes a temperature and has no thinking level.
        XCTAssertEqual(config["temperature"] as? Double, 0.8)
        XCTAssertNil(config["thinkingConfig"])
    }

    func testGemini3UsesTheLowestThinkingLevelAndNoTemperature() async throws {
        stub { _ in .json(["candidates": [["content": ["parts": [["text": "ok"]]]]]]) }
        let expected: [String: String?] = [
            "gemini-3.5-flash-lite": nil,   // already minimal by default
            "gemini-3.6-flash": "MINIMAL",
            "gemini-3.8-flash": "LOW",      // rejects MINIMAL
            "gemini-4-argon": "LOW",
        ]
        for (model, level) in expected {
            _ = try await GeminiProvider(apiKey: "k", model: model).generate(messages: conversation, systemPrompt: "S")
            let config = try XCTUnwrap(try lastRequest().json["generationConfig"] as? [String: Any])
            XCTAssertNil(config["temperature"], model)
            XCTAssertEqual((config["thinkingConfig"] as? [String: String])?["thinkingLevel"], level, model)
        }
    }

    func testGeminiSkipsThoughtPartsAndJoinsTheText() async throws {
        stub { _ in .json(["candidates": [["content": ["parts": [
            ["text": "planning", "thought": true],
            ["text": "[happy] Hi ", "thoughtSignature": "sig"],
            ["text": "there"],
        ]]]]]) }
        let reply = try await GeminiProvider(apiKey: "k", model: "gemini-3.6-flash")
            .generate(messages: conversation, systemPrompt: "S")
        XCTAssertEqual(reply, "[happy] Hi there")
    }

    func testGeminiVisionAttachesTheImageToTheLastUserMessage() async throws {
        stub { _ in .json(["candidates": [["content": ["parts": [["text": "A red square"]]]]]]) }
        _ = try await GeminiProvider(apiKey: "k", model: "m")
            .generateWithVision(messages: conversation, systemPrompt: "S", image: image())

        let sent = try lastRequest()
        XCTAssertNil(sent.request.url?.query, "The API key must not be sent in the URL")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "x-goog-api-key"), "k")
        let contents = try XCTUnwrap(sent.json["contents"] as? [[String: Any]])
        let lastParts = try XCTUnwrap(contents.last?["parts"] as? [[String: Any]])
        XCTAssertEqual(lastParts.first?["text"] as? String, "What do you see?")
        let inline = try XCTUnwrap(lastParts.last?["inline_data"] as? [String: String])
        XCTAssertEqual(inline["mime_type"], "image/jpeg")
        XCTAssertNotNil(Data(base64Encoded: inline["data"] ?? ""))
        XCTAssertEqual((contents.first?["parts"] as? [[String: Any]])?.count, 1, "Only the last user turn carries the image")
    }

    // MARK: - OpenAI

    func testOpenAIRequestAndReply() async throws {
        stub { _ in .json(Self.openAIReply) }
        let reply = try await OpenAIProvider(apiKey: "sk-test", model: "gpt-6-luna")
            .generate(messages: conversation, systemPrompt: "SYSTEM")
        XCTAssertEqual(reply, "[happy] Stubbed reply")

        let sent = try lastRequest()
        XCTAssertEqual(sent.request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(sent.json["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(sent.json["max_completion_tokens"] as? Int, 4096)
        XCTAssertEqual(sent.json["reasoning_effort"] as? String, "none")
        XCTAssertNil(sent.json["temperature"])
        let messages = try XCTUnwrap(sent.json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.compactMap { $0["role"] as? String }, ["system", "user", "assistant", "user"])
        XCTAssertEqual(messages.first?["content"] as? String, "SYSTEM")
    }

    func testOpenAIVisionSendsAnImageURLPart() async throws {
        stub { _ in .json(Self.openAIReply) }
        _ = try await OpenAIProvider(apiKey: "k", model: "gpt-5.4-mini")
            .generateWithVision(messages: conversation, systemPrompt: "S", image: image())
        let messages = try XCTUnwrap(try lastRequest().json["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.map { $0["type"] as? String }, ["text", "image_url"])
        let imageURL = try XCTUnwrap((parts.last?["image_url"] as? [String: String])?["url"])
        XCTAssertTrue(imageURL.hasPrefix("data:image/jpeg;base64,"))
    }

    func testOpenAIReasoningEffortIsTheLowestEachModelAccepts() {
        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: "gpt-6-luna"), "none")
        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: "gpt-5.6-terra"), "none")
        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: "gpt-6.1-sol"), "low")
        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: "gpt-6-astra"), "low")
        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: "gpt-5-mini"), "minimal")
        XCTAssertNil(OpenAIProvider.reasoningEffort(for: "my-fine-tune"))
    }

    // MARK: - Claude

    func testClaudeRequestAndReply() async throws {
        stub { _ in .json(["content": [["type": "text", "text": "[thinking] Let me see"]]]) }
        let reply = try await ClaudeProvider(apiKey: "anthropic-key", model: "claude-sonnet-5-5")
            .generate(messages: conversation, systemPrompt: "SYSTEM")
        XCTAssertEqual(reply, "[thinking] Let me see")

        let sent = try lastRequest()
        XCTAssertEqual(sent.request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(sent.json["system"] as? String, "SYSTEM")
        let messages = try XCTUnwrap(sent.json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.compactMap { $0["role"] as? String }, ["user", "assistant", "user"])
    }

    func testClaudeSkipsThinkingBlocksAndJoinsTheText() async throws {
        stub { _ in .json(["content": [
            ["type": "thinking", "thinking": "", "signature": "sig"],
            ["type": "text", "text": "[happy] Hello "],
            ["type": "text", "text": "there"],
        ], "stop_reason": "end_turn"]) }
        let reply = try await ClaudeProvider(apiKey: "k", model: "claude-opus-5-5")
            .generate(messages: conversation, systemPrompt: "S")
        XCTAssertEqual(reply, "[happy] Hello there")
    }

    func testClaudeRefusalSurfacesAReadableError() async throws {
        stub { _ in .json(["content": [], "stop_reason": "refusal"]) }
        do {
            _ = try await ClaudeProvider(apiKey: "k", model: "claude-sonnet-5-5")
                .generate(messages: conversation, systemPrompt: "S")
            XCTFail("a refusal must not return a reply")
        } catch LLMError.serverError(_, let message) {
            XCTAssertTrue(message.contains("declined"))
        }
    }

    func testCurrentClaudeModelsUseLowEffortAndServerFallbacks() async throws {
        stub { _ in .json(["content": [["type": "text", "text": "ok"]]]) }
        _ = try await ClaudeProvider(apiKey: "k", model: "claude-sonnet-5-5")
            .generate(messages: conversation, systemPrompt: "S")
        let sent = try lastRequest()
        XCTAssertEqual((sent.json["output_config"] as? [String: String])?["effort"], "low")
        XCTAssertEqual(sent.json["fallbacks"] as? String, "default")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertEqual(sent.json["max_tokens"] as? Int, 8192)
        XCTAssertNil(sent.json["temperature"], "current Claude models reject sampling parameters")
    }

    func testClaudeHaikuGetsNeitherEffortNorFallbacks() async throws {
        stub { _ in .json(["content": [["type": "text", "text": "ok"]]]) }
        _ = try await ClaudeProvider(apiKey: "k", model: "claude-haiku-4-5")
            .generate(messages: conversation, systemPrompt: "S")
        let sent = try lastRequest()
        XCTAssertNil(sent.json["output_config"], "Haiku 4.5 rejects the effort parameter")
        XCTAssertNil(sent.json["fallbacks"])
        XCTAssertNil(sent.request.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testClaudeVisionSendsABase64ImageBlock() async throws {
        stub { _ in .json(["content": [["type": "text", "text": "ok"]]]) }
        _ = try await ClaudeProvider(apiKey: "k", model: "m")
            .generateWithVision(messages: conversation, systemPrompt: "S", image: image())
        let messages = try XCTUnwrap(try lastRequest().json["messages"] as? [[String: Any]])
        let blocks = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let source = try XCTUnwrap(blocks.last?["source"] as? [String: String])
        XCTAssertEqual(source["type"], "base64")
        XCTAssertEqual(source["media_type"], "image/jpeg")
    }

    // MARK: - OpenAI-compatible and Ollama

    func testMoonshotTurnsThinkingDownForSpokenReplies() async throws {
        stub { _ in .json(Self.openAIReply) }
        let k26 = OpenAICompatibleProvider(
            baseURL: "https://api.moonshot.ai/v1", apiKey: "k", model: "kimi-k2.6",
            includeTemperature: AIProvider.moonshot.includesSamplingTemperature,
            extraBody: AIProvider.moonshot.extraRequestFields(for: "kimi-k2.6")
        )
        _ = try await k26.generate(messages: conversation, systemPrompt: "S")
        let sent = try lastRequest().json
        XCTAssertEqual((sent["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertNil(sent["temperature"], "Kimi models reject any temperature but their fixed one")

        XCTAssertEqual(AIProvider.moonshot.extraRequestFields(for: "kimi-k3")["reasoning_effort"] as? String, "low")
        XCTAssertTrue(AIProvider.groq.extraRequestFields(for: "openai/gpt-oss-20b").isEmpty)
    }

    func testOpenAICompatibleProviderBuildsTheEndpointAndOptionalSampling() async throws {
        stub { _ in .json(Self.openAIReply) }
        let provider = OpenAICompatibleProvider(
            baseURL: "https://api.moonshot.ai/v1/",
            apiKey: "moon",
            model: "kimi-k2.6",
            extraHeaders: ["X-Title": "Scowld"],
            includeTemperature: false
        )
        _ = try await provider.generate(messages: conversation, systemPrompt: "S")

        let sent = try lastRequest()
        XCTAssertEqual(sent.request.url?.absoluteString, "https://api.moonshot.ai/v1/chat/completions")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer moon")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "X-Title"), "Scowld")
        XCTAssertNil(sent.json["temperature"], "Moonshot rejects custom sampling values")
        XCTAssertEqual(sent.json["max_tokens"] as? Int, 1024)

        _ = try await OpenAICompatibleProvider(baseURL: "https://api.groq.com/openai/v1", apiKey: "g", model: "m")
            .generate(messages: conversation, systemPrompt: "S")
        let groq = try lastRequest()
        XCTAssertEqual(groq.request.url?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(groq.json["temperature"] as? Double, 0.8)
    }

    func testOllamaUsesTheLocalChatEndpointWithoutStreaming() async throws {
        stub { _ in .json(["message": ["role": "assistant", "content": "[neutral] Local reply"]]) }
        let reply = try await OllamaProvider(baseURL: "http://192.168.1.20:11434/", model: "llama3.2")
            .generateWithVision(messages: conversation, systemPrompt: "S", image: image())
        XCTAssertEqual(reply, "[neutral] Local reply")

        let sent = try lastRequest()
        XCTAssertEqual(sent.request.url?.absoluteString, "http://192.168.1.20:11434/api/chat")
        XCTAssertEqual(sent.json["stream"] as? Bool, false)
        XCTAssertNil(sent.request.value(forHTTPHeaderField: "Authorization"))
        let messages = try XCTUnwrap(sent.json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertTrue(messages.last?["content"]?.hasPrefix("What do you see?\n(Note: Image was provided") == true,
                      "Ollama falls back to text and says an image was skipped")
    }

    // MARK: - Errors

    func testRateLimitServerErrorsAndMalformedRepliesAreReported() async throws {
        stub { _ in .text("slow down", status: 429) }
        do {
            _ = try await OpenAIProvider(apiKey: "k", model: "m").generate(messages: conversation, systemPrompt: "S")
            XCTFail("expected rate limit")
        } catch LLMError.rateLimited {}

        StubURLProtocol.install { _ in .text("upstream exploded", status: 503) }
        do {
            _ = try await ClaudeProvider(apiKey: "k", model: "m").generate(messages: conversation, systemPrompt: "S")
            XCTFail("expected server error")
        } catch LLMError.serverError(let code, let body) {
            XCTAssertEqual(code, 503)
            XCTAssertEqual(body, "upstream exploded")
        }

        StubURLProtocol.install { _ in .json(["unexpected": true]) }
        do {
            _ = try await GeminiProvider(apiKey: "k", model: "m").generate(messages: conversation, systemPrompt: "S")
            XCTFail("expected invalid response")
        } catch LLMError.invalidResponse {}

        XCTAssertEqual(LLMError.noAPIKey.errorDescription, "No API key configured. Add your key in Settings.")
        XCTAssertEqual(LLMError.serverError(500, "x").errorDescription, "Server error (500): x")
    }
}
