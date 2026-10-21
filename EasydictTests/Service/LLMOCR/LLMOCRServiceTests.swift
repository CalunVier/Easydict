//
//  LLMOCRServiceTests.swift
//  EasydictTests
//
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Defaults
import Foundation
import Testing

@testable import Easydict

/// Uses only the workflow's loopback HTTP fixture and generated pixels, never a live provider.
@Suite(
    "LLM OCR Service",
    .tags(.ocr, .integration),
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["EASYDICT_LLM_OCR_TEST_ENDPOINT"] != nil)
)
@MainActor
struct LLMOCRServiceTests {
    @Test("Actual service preserves transcription and never supplies translated text")
    func mapsServiceResult() async throws {
        try await withFixture {
            let result = try #require(try await LLMOCRService().ocr(
                syntheticImage(), from: .english, to: .simplifiedChinese
            ))
            #expect(result.mergedText == Self.expectedText)
            #expect(result.texts == [Self.expectedText])
            #expect(result.ocrTextArray.count == 1)
            let block = try #require(result.ocrTextArray.first)
            #expect(block.text == Self.expectedText)
            #expect(block.translatedText == nil)
            #expect(result.from == .english)
            #expect(result.to == .simplifiedChinese)
        }
    }

    @Test("DetectManager selects LLM OCR and updates the original text pipeline")
    func updatesOriginalTextPipeline() async throws {
        try await withFixture {
            let model = try modelWithImage()
            let manager = DetectManager(model: model)
            let completion = Completion()
            manager.ocrAndDetectText { updated, error in
                completion.count += 1
                completion.error = error
                completion.model = updated
            }
            try await waitUntil { completion.count > 0 }
            #expect(completion.count == 1)
            #expect(completion.error == nil)
            #expect(completion.model === model)
            #expect(manager.ocrService is LLMOCRService)
            #expect(!(manager.ocrService is AppleService))
            #expect(model.inputText == Self.expectedText)
            #expect(model.detectedLanguage == .english)
        }
    }

    @Test("HTTP failure resolves completion without overwriting the user's source text")
    func resolvesHTTPFailure() async throws {
        try await withFixture {
            Defaults[.llmOCRModel] = "fixture-http-error"
            let model = try modelWithImage()
            let manager = DetectManager(model: model)
            let completion = Completion()
            manager.ocrAndDetectText { _, error in
                completion.count += 1
                completion.error = error
            }
            try await waitUntil { completion.count > 0 }
            #expect(completion.count == 1)
            #expect(completion.error as? LLMOCRError == .httpStatus(503))
            #expect(model.inputText == "Original source")
            #expect(manager.ocrService is LLMOCRService)
        }
    }

    @Test("Input edited during OCR is not replaced by the stale transcription")
    func rejectsChangedInput() async throws {
        try await withFixture {
            let delayedModel = "fixture-delay-\(UUID().uuidString)"
            Defaults[.llmOCRModel] = delayedModel
            let model = try modelWithImage()
            let manager = DetectManager(model: model)
            let completion = Completion()
            manager.ocrAndDetectText { _, error in
                completion.count += 1
                completion.error = error
            }
            try await waitForAccepted(model: delayedModel)
            model.inputText = "User edited this while OCR was running"
            _ = try await fixtureControl(path: "/release", model: delayedModel)
            try await waitUntil { completion.count > 0 }
            #expect(completion.count == 1)
            #expect((completion.error as? URLError)?.code == .cancelled)
            #expect(model.inputText == "User edited this while OCR was running")
        }
    }

    @Test("A replacement request resolves both callbacks and only the latest result wins")
    func cancelsSupersededRequest() async throws {
        try await withFixture {
            let delayedModel = "fixture-delay-\(UUID().uuidString)"
            Defaults[.llmOCRModel] = delayedModel
            let model = try modelWithImage()
            let manager = DetectManager(model: model)
            let first = Completion()
            manager.ocrAndDetectText { _, error in
                first.count += 1
                first.error = error
            }
            try await waitForAccepted(model: delayedModel)
            Defaults[.llmOCRModel] = "fixture-success"
            let second = Completion()
            manager.ocrAndDetectText { _, error in
                second.count += 1
                second.error = error
            }
            try await waitUntil { first.count > 0 && second.count > 0 }
            _ = try await fixtureControl(path: "/release", model: delayedModel)
            #expect(first.count == 1)
            #expect((first.error as? URLError)?.code == .cancelled)
            #expect(second.count == 1)
            #expect(second.error == nil)
            #expect(model.inputText == Self.expectedText)
        }
    }

    @Test("Missing image resolves completion instead of leaving the caller waiting")
    func resolvesMissingImage() async throws {
        try await withFixture {
            let manager = DetectManager(model: QueryModel())
            let completion = Completion()
            manager.ocr { result, error in
                completion.count += 1
                completion.error = error
                #expect(result == nil)
            }
            try await waitUntil { completion.count > 0 }
            #expect(completion.count == 1)
            #expect(completion.error != nil)
        }
    }

    private static let expectedText = "First paragraph.\n\n| Name | Value |\n| --- | --- |\n| x | $x^2$ |\n\n$$\\int_0^1 x\\,dx=\\frac{1}{2}$$\n"

    private final class Completion {
        var count = 0
        var error: Error?
        var model: QueryModel?
    }

    private enum FixtureError: Error {
        case timedOut
        case invalidEndpoint
        case invalidControlResponse
    }

    /// Restore every changed preference even when a test throws or records a failure.
    private func withFixture(_ operation: () async throws -> Void) async throws {
        let endpoint = try fixtureEndpoint()
        let savedEnabled = Defaults[.enableLLMOCR]
        let savedEndpoint = Defaults[.llmOCREndpoint]
        let savedModel = Defaults[.llmOCRModel]
        let savedKey = Defaults[.llmOCRAPIKey]
        defer {
            Defaults[.enableLLMOCR] = savedEnabled
            Defaults[.llmOCREndpoint] = savedEndpoint
            Defaults[.llmOCRModel] = savedModel
            Defaults[.llmOCRAPIKey] = savedKey
        }
        Defaults[.enableLLMOCR] = true
        Defaults[.llmOCREndpoint] = endpoint.absoluteString
        Defaults[.llmOCRModel] = "fixture-success"
        Defaults[.llmOCRAPIKey] = ""
        try await operation()
    }

    private func fixtureEndpoint() throws -> URL {
        let value = try #require(ProcessInfo.processInfo.environment["EASYDICT_LLM_OCR_TEST_ENDPOINT"])
        guard let url = URL(string: value), url.scheme == "http", url.host == "127.0.0.1",
              url.user == nil, url.password == nil, url.path == "/v1/chat/completions" else {
            throw FixtureError.invalidEndpoint
        }
        return url
    }

    private func syntheticImage() throws -> NSImage {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let pixels = try #require(bitmap.bitmapData)
        pixels.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let image = NSImage(size: NSSize(width: 32, height: 24))
        image.addRepresentation(bitmap)
        return image
    }

    private func modelWithImage() throws -> QueryModel {
        let model = QueryModel()
        model.inputText = "Original source"
        model.userSourceLanguage = .english
        model.userTargetLanguage = .simplifiedChinese
        model.ocrImage = try syntheticImage()
        return model
    }

    /// Poll only under a fixed deadline; accepted/release gates establish request ordering.
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !predicate() {
            guard Date() < deadline else { throw FixtureError.timedOut }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func waitForAccepted(model: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        while true {
            let state = try await fixtureControl(path: "/state", model: model)
            if state["accepted"] == true { return }
            guard Date() < deadline else { throw FixtureError.timedOut }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func fixtureControl(path: String, model: String) async throws -> [String: Bool] {
        var components = try #require(URLComponents(url: fixtureEndpoint(), resolvingAgainstBaseURL: false))
        components.path = path
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        var request = URLRequest(url: try #require(components.url))
        request.timeoutInterval = 2
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let state = try JSONSerialization.jsonObject(with: data) as? [String: Bool] else {
            throw FixtureError.invalidControlResponse
        }
        return state
    }
}
