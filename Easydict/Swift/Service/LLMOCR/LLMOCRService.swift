//
//  LLMOCRService.swift
//  Easydict
//
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Foundation

/// Adapts transcription to the existing OCR boundary without joining the translation registry.
final class LLMOCRService: QueryService {
    override func ocr(
        _ image: NSImage,
        from: Language,
        to: Language
    ) async throws -> EZOCRResult? {
        let configuration = LLMOCRConfiguration.current
        _ = try configuration.validatedEndpoint()
        try Task.checkCancellation()
        guard let imageData = image.pngData() else { throw LLMOCRError.invalidImage }
        let text = try await client.recognize(imageData: imageData, configuration: configuration)
        try Task.checkCancellation()

        let result = EZOCRResult()
        let recognizedText = EZOCRText()
        recognizedText.text = text
        // One text block avoids lossy line splitting and preserves Markdown/LaTeX layout.
        result.ocrTextArray = [recognizedText]
        result.texts = [text]
        result.mergedText = text
        result.from = from == .auto ? AppleLanguageDetector().detectLanguage(text: text) : from
        result.to = to
        // No translatedText, raw provider payload, geometry, or fabricated confidence.
        return result
    }

    private let client = LLMOCRClient()
}
