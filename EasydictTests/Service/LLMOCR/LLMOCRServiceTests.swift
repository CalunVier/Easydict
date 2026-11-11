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
            let model = try await modelWithImage()
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
            let model = try await modelWithImage()
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

    private func modelWithImage() async throws -> QueryModel {
        let model = QueryModel()
        // Drain the initial language preference publishers before setting the snapshot.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
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

}
