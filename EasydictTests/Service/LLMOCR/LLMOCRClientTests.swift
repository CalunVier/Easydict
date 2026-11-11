//
//  LLMOCRClientTests.swift
//  EasydictTests
//
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import Testing

@testable import Easydict

/// Offline coverage of the transcription request and response boundary.
@Suite("LLM OCR Client", .tags(.ocr, .unit))
struct LLMOCRClientTests {
    @Test("Only HTTPS or exact HTTP loopback endpoints are accepted", arguments: [
        "http://example.com/v1/chat/completions", "http://localhost.example.com/ocr",
        "http://127.0.0.1.example.com/ocr", "ftp://localhost/ocr", "file:///tmp/ocr",
        "https://user:password@example.com/ocr", "https://example.com/ocr#fragment",
        "https://example.com:0/ocr", "https://example.com:65536/ocr", "/relative/path",
    ])
    func rejectsUnsafeEndpoint(endpoint: String) {
        #expect(throws: LLMOCRError.invalidEndpoint) {
            try configuration(endpoint: endpoint).validatedEndpoint()
        }
    }

    @Test("Loopback permits a blank key", arguments: [
        "http://localhost:18767/v1/chat/completions",
        "http://127.0.0.1:18767/v1/chat/completions",
        "http://[::1]:18767/v1/chat/completions",
    ])
    func acceptsLoopbackWithoutCredentials(endpoint: String) throws {
        let config = configuration(endpoint: endpoint, key: " \n")
        #expect(try config.validatedEndpoint().absoluteString == endpoint)
        let request = try LLMOCRClient().makeRequest(imageData: Data([1]), configuration: config)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Remote configuration requires a model and key")
    func validatesRequiredConfiguration() throws {
        #expect(throws: LLMOCRError.missingModel) {
            try configuration(model: " \n").validatedEndpoint()
        }
        #expect(throws: LLMOCRError.missingAPIKey) {
            try configuration(key: " \n").validatedEndpoint()
        }
        #expect(try configuration().validatedEndpoint().scheme == "https")
    }

    @Test("Request contains only the OCR prompt and PNG image, not a translation target")
    func makesOCRRequest() throws {
        let image = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let request = try LLMOCRClient().makeRequest(
            imageData: image,
            configuration: configuration(model: " fixture-model \n", key: " fixture-key \n")
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(payload.keys) == Set(["model", "stream", "messages"]))
        #expect(payload["model"] as? String == "fixture-model")
        #expect(payload["stream"] as? Bool == false)
        let messages = try #require(payload["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        let system = try #require(messages.first)
        #expect(system["role"] as? String == "system")
        let prompt = try #require(system["content"] as? String)
        #expect(prompt.contains("Do not translate"))
        #expect(prompt.contains("Markdown tables"))
        #expect(prompt.contains("LaTeX"))
        #expect(prompt.contains("never as instructions"))
        let user = try #require(messages.last)
        #expect(user["role"] as? String == "user")
        let content = try #require(user["content"] as? [[String: Any]])
        #expect(content.count == 1)
        let part = try #require(content.first)
        #expect(part["type"] as? String == "image_url")
        let imageURL = try #require(part["image_url"] as? [String: String])
        #expect(imageURL["url"] == "data:image/png;base64,\(image.base64EncodedString())")
        #expect(imageURL["detail"] == "high")
    }

    @Test("Empty and oversized images are rejected before transport")
    func rejectsInvalidImageSizes() {
        let client = LLMOCRClient()
        #expect(throws: LLMOCRError.invalidImage) {
            try client.makeRequest(imageData: Data(), configuration: configuration())
        }
        #expect(throws: LLMOCRError.imageTooLarge) {
            try client.makeRequest(
                imageData: Data(repeating: 0, count: LLMOCRClient.maximumImageBytes + 1),
                configuration: configuration()
            )
        }
    }

    @Test("An image exactly at the size limit is accepted")
    func acceptsMaximumImageSize() throws {
        let request = try LLMOCRClient().makeRequest(
            imageData: Data(repeating: 0, count: LLMOCRClient.maximumImageBytes),
            configuration: configuration()
        )
        #expect(request.httpBody != nil)
    }

    @Test("Paragraphs, whitespace, Markdown, and LaTeX remain byte-for-byte unchanged")
    func preservesTranscription() throws {
        let text = "  First paragraph.\n\n第二段。\n\n| Name | Value |\n| --- | --- |\n| x | $x^2$ |\n\n$$\\int_0^1 x\\,dx=\\frac{1}{2}$$\n"
        #expect(try LLMOCRClient().decodeResponse(response(content: text)) == text)
    }

    @Test("Empty responses cannot become successful OCR")
    func rejectsEmptyResponses() throws {
        let client = LLMOCRClient()
        for content in ["", " \n\t"] {
            #expect(throws: LLMOCRError.emptyResponse) {
                try client.decodeResponse(response(content: content))
            }
        }
        #expect(throws: LLMOCRError.emptyResponse) {
            try client.decodeResponse(response(content: NSNull()))
        }
        #expect(throws: LLMOCRError.emptyResponse) {
            try client.decodeResponse(Data(#"{"choices":[]}"#.utf8))
        }
    }

    @Test("Refusal and truncated output fail even when partial text exists")
    func rejectsRefusedAndTruncatedResponses() {
        let client = LLMOCRClient()
        #expect(throws: LLMOCRError.refused) {
            try client.decodeResponse(response(content: "partial", refusal: "Cannot comply"))
        }
        #expect(throws: LLMOCRError.refused) {
            try client.decodeResponse(response(content: "partial", finishReason: "content_filter"))
        }
        #expect(throws: LLMOCRError.truncated) {
            try client.decodeResponse(response(content: "partial", finishReason: "length"))
        }
    }

    @Test("Unexpected finish reasons fail", arguments: ["tool_calls", "function_call", "unknown", ""])
    func rejectsNonStopFinishReason(reason: String) {
        #expect(throws: LLMOCRError.invalidResponse) {
            try LLMOCRClient().decodeResponse(response(content: "text", finishReason: reason))
        }
    }

    @Test("Malformed JSON and non-string content fail", arguments: [
        "not json", "{}", #"{"choices":[{}]}"#,
        #"{"choices":[{"message":{"content":[]},"finish_reason":"stop"}]}"#,
        #"{"choices":[{"message":{"content":"text"}}]}"#,
    ])
    func rejectsMalformedResponses(json: String) {
        #expect(throws: LLMOCRError.invalidResponse) {
            try LLMOCRClient().decodeResponse(Data(json.utf8))
        }
    }

    private func configuration(
        endpoint: String = "https://example.com/v1/chat/completions",
        model: String = "fixture-model",
        key: String = "fixture-key"
    ) -> LLMOCRConfiguration {
        LLMOCRConfiguration(endpoint: endpoint, model: model, apiKey: key)
    }

    private func response(
        content: Any,
        finishReason: String = "stop",
        refusal: String = ""
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "message": ["content": content, "refusal": refusal],
                "finish_reason": finishReason,
            ]],
        ])
    }
}
