//
//  LLMOCRConfigurationView.swift
//  Easydict
//
//  Copyright © 2026 izual. All rights reserved.
//

import Defaults
import SFSafeSymbols
import SwiftUI

// MARK: - LLMOCRConfigurationView

/// Configures transcription independently of the translation services, without sending requests.
struct LLMOCRConfigurationView: View {
    // MARK: Internal

    var body: some View {
        Group {
            Toggle(isOn: $enableLLMOCR) {
                AdvancedTabItemView(
                    color: .indigo,
                    icon: .docViewfinder,
                    labelText: "ocr.llm.enable",
                    subtitleText: "ocr.llm.description"
                )
            }

            Text("ocr.llm.privacy_notice")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if enableLLMOCR {
                TextField("ocr.llm.endpoint", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                Text("ocr.llm.endpoint_hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("ocr.llm.model", text: $model)
                    .textFieldStyle(.roundedBorder)
                Text("ocr.llm.model_hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureTextField(
                    title: "ocr.llm.api_key",
                    placeholder: String(localized: "ocr.llm.api_key_placeholder"),
                    text: $apiKey
                )
                .textFieldStyle(.roundedBorder)
                Text("ocr.llm.api_key_hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Private

    @Default(.enableLLMOCR) private var enableLLMOCR
    @Default(.llmOCREndpoint) private var endpoint
    @Default(.llmOCRModel) private var model
    @Default(.llmOCRAPIKey) private var apiKey
}
