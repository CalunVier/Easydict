//
//  LLMOCRConfiguration.swift
//  Easydict
//
//  Copyright © 2026 izual. All rights reserved.
//

import Defaults
import Foundation

extension Defaults.Keys {
    static let enableLLMOCR = Key<Bool>("enableLLMOCR", default: false)
    static let llmOCREndpoint = Key<String>(
        "llmOCREndpoint",
        default: "https://api.openai.com/v1/chat/completions"
    )
    static let llmOCRModel = Key<String>("llmOCRModel", default: "")
    static let llmOCRAPIKey = Key<String>("llmOCRAPIKey", default: "")
}

/// A per-request snapshot, independent of translation service configuration.
struct LLMOCRConfiguration: Sendable {
    let endpoint: String
    let model: String
    let apiKey: String

    static var current: LLMOCRConfiguration {
        LLMOCRConfiguration(
            endpoint: Defaults[.llmOCREndpoint],
            model: Defaults[.llmOCRModel],
            apiKey: Defaults[.llmOCRAPIKey]
        )
    }

    /// Validate before encoding or transmitting any screenshot data.
    func validatedEndpoint() throws -> URL {
        let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: endpoint),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil,
              let url = components.url else {
            throw LLMOCRError.invalidEndpoint
        }

        // Exact loopback names avoid trusting suffixes such as localhost.example.com.
        let isLoopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard scheme == "https" || (scheme == "http" && isLoopback),
              components.port.map({ (1 ... 65535).contains($0) }) ?? true else {
            throw LLMOCRError.invalidEndpoint
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMOCRError.missingModel
        }
        guard isLoopback || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMOCRError.missingAPIKey
        }
        return url
    }
}

/// Safe user-facing errors never contain request headers, screenshot data, or raw server bodies.
enum LLMOCRError: Error, LocalizedError, Equatable {
    case invalidEndpoint
    case missingModel
    case missingAPIKey
    case invalidImage
    case imageTooLarge
    case network
    case httpStatus(Int)
    case invalidResponse
    case emptyResponse
    case refused
    case truncated

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return String(localized: "ocr.llm.error.invalid_endpoint")
        case .missingModel:
            return String(localized: "ocr.llm.error.missing_model")
        case .missingAPIKey:
            return String(localized: "ocr.llm.error.missing_api_key")
        case .invalidImage:
            return String(localized: "ocr.llm.error.invalid_image")
        case .imageTooLarge:
            return String(localized: "ocr.llm.error.image_too_large")
        case .network:
            return String(localized: "ocr.llm.error.network")
        case let .httpStatus(status):
            return String(format: String(localized: "ocr.llm.error.http_status %lld"), Int64(status))
        case .invalidResponse:
            return String(localized: "ocr.llm.error.invalid_response")
        case .emptyResponse:
            return String(localized: "ocr.llm.error.empty_response")
        case .refused:
            return String(localized: "ocr.llm.error.refused")
        case .truncated:
            return String(localized: "ocr.llm.error.truncated")
        }
    }
}
