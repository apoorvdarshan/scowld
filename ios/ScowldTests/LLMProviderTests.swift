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
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "key" }?.value, "test-key")
        XCTAssertEqual(sent.request.httpMethod, "POST")

        let contents = try XCTUnwrap(sent.json["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.compactMap { $0["role"] as? String }, ["user", "model", "user"])
        let system = try XCTUnwrap(sent.json["systemInstruction"] as? [String: Any])
        XCTAssertEqual((system["parts"] as? [[String: String]])?.first?["text"], "SYSTEM")
        let config = try XCTUnwrap(sent.json["generationConfig"] as? [String: Any])
        XCTAssertEqual(config["maxOutputTokens"] as? Int, 1024)
    }

    func testGeminiVisionAttachesTheImageToTheLastUserMessage() async throws {
        stub { _ in .json(["candidates": [["content": ["parts": [["text": "A red square"]]]]]]) }
        _ = try await GeminiProvider(apiKey: "k", model: "m")
            .generateWithVision(messages: conversation, systemPrompt: "S", image: image())

        let contents = try XCTUnwrap(try lastRequest().json["contents"] as? [[String: Any]])
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
        let reply = try await OpenAIProvider(apiKey: "sk-test", model: "gpt-4.1")
            .generate(messages: conversation, systemPrompt: "SYSTEM")
        XCTAssertEqual(reply, "[happy] Stubbed reply")

        let sent = try lastRequest()
        XCTAssertEqual(sent.request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(sent.json["model"] as? String, "gpt-4.1")
        XCTAssertEqual(sent.json["max_completion_tokens"] as? Int, 1024)
        let messages = try XCTUnwrap(sent.json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.compactMap { $0["role"] as? String }, ["system", "user", "assistant", "user"])
        XCTAssertEqual(messages.first?["content"] as? String, "SYSTEM")
    }

    func testOpenAIVisionSendsAnImageURLPart() async throws {
        stub { _ in .json(Self.openAIReply) }
        _ = try await OpenAIProvider(apiKey: "k", model: "gpt-4o")
            .generateWithVision(messages: conversation, systemPrompt: "S", image: image())
        let messages = try XCTUnwrap(try lastRequest().json["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.map { $0["type"] as? String }, ["text", "image_url"])
        let imageURL = try XCTUnwrap((parts.last?["image_url"] as? [String: String])?["url"])
        XCTAssertTrue(imageURL.hasPrefix("data:image/jpeg;base64,"))
    }

    // MARK: - Claude

    func testClaudeRequestAndReply() async throws {
        stub { _ in .json(["content": [["type": "text", "text": "[thinking] Let me see"]]]) }
        let reply = try await ClaudeProvider(apiKey: "anthropic-key", model: "claude-sonnet-4-6")
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
