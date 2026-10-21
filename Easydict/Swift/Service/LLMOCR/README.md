# LLM OCR

This optional OCR adapter transcribes an image and returns an `EZOCRResult`.
The existing screenshot, clipboard and HTTP OCR entry points continue to use
`DetectManager`; translation still receives text through the existing pipeline.
It is not a translation provider and is not registered in the translation service list.

## Configuration

In Settings → Advanced → OCR, enable LLM OCR and enter a complete
OpenAI-compatible Chat Completions URL, a vision-capable model, and an API key.
The default remains local Apple OCR. No request is sent merely by opening or editing
settings. The independent OCR configuration does not modify translation settings.

The endpoint must use HTTPS; HTTP is accepted only for `localhost`, `127.0.0.1`,
or `::1`. A key is optional for these loopback endpoints. Redirects are not followed.
Images are PNG data URLs, limited to 20 MiB before base64 encoding. The provider
may impose a smaller limit or charge per request. No silent cloud-provider fallback
or automatic retry sends the image elsewhere.

## Boundaries

- `LLMOCRConfiguration`: persisted settings and immutable request snapshots.
- `LLMOCRClient`: non-streaming request construction, transport and response decoding.
- `LLMOCRService`: image conversion and adaptation to the existing OCR result type.
- `LLMOCRConfigurationView`: settings and upload/cost disclosure.

The OCR prompt preserves original languages, paragraphs, Markdown tables and LaTeX
math. No target language or translation prompt is sent to the model. Screenshot text
is treated as transcription input, not instructions. Model adherence and recognition
accuracy are not guaranteed; inspect important output before relying on it.

Only standard Chat Completions string content with `finish_reason: "stop"` is
accepted. Empty, refused, truncated or unsupported responses are errors, not partial
translations. The service does not invent confidence scores, word geometry or
translated text. Automatic source-language detection is local.

`DetectManager` cancels a superseded OCR task and checks its request identity,
image, input and language snapshot before applying the response. The screenshot
controller checks the current model and image before updating UI or copying text.

## Verification status

Implementation is not yet compiled or tested on macOS. Dedicated offline client
tests and a loopback HTTP fixture exercise request construction, result mapping,
errors and superseded requests. The GitHub Actions workflow forwards the fixture
endpoint to the test runner and requires the integration suite to actually pass.
Live provider validation requires
an explicitly authorized endpoint/model and credentials; none have been used.
The prior Markdown CI does not validate this feature.
