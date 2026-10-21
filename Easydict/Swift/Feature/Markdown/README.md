# Translation Markdown rendering

AI result presentation is isolated here; dictionary HTML and translation providers are unchanged.

## Components

- `RichMarkdownView.swift`: AppKit/WebKit adapter. It owns an ephemeral web view, coalesces
  streaming updates, rejects obsolete height messages, opens user-activated HTTP(S)/mailto links
  in the system handler, and falls back to original text on a renderer/process failure.
- `WebRenderer/`: separate parser and DOM presentation sources, exact npm versions, lockfile, and asset builder.
- `MarkdownResources/`: checked-in offline runtime, KaTeX fonts, third-party licenses and SHA-256
  manifest. A folder reference copies the directory into the application bundle. Ordinary Xcode
  builds do not invoke npm or download web resources.
- `MarkdownRenderer.swift` / `MarkdownLabel.swift`: legacy attributed-string renderer retained
  for compatibility and existing tests; rich result presentation no longer depends on it.
- `EZWordResultView`: small integration boundary for the existing toggle, font size, result identity
  and asynchronous row height. Result toolbar copy continues to copy original Markdown.

## Supported output

Markdown-it parses headings, paragraphs, nested lists, blockquotes, links, escaped punctuation,
code spans/fences, rules, strikethrough and tables. KaTeX renders `$...$`, `$$...$$`, `\(...\)` and
`\[...\]` expressions (including supported fractions, matrices and aligned equations).
An incomplete formula remains readable until the closing delimiter arrives. This is not a full
TeX engine: arbitrary packages, custom scripts and unsupported commands are not executed.
Code blocks use monospace text without syntax highlighting. Remote images render their alt text;
arbitrary HTML is displayed as text. Task-list checkboxes and footnote extensions are not enabled.

Tables and display equations scroll horizontally rather than widening the translation window.
Long results have a bounded viewport. Font loading and width changes report updated content heights.
Streaming updates preserve a live text selection until it is released; final content is then applied.
KaTeX output is cached by exact formula and display mode with a 128-entry / 1 MiB string budget.
Every cache miss uses fresh macro state. Unchanged same-position top-level DOM blocks are retained,
including completed formulas and table scroll containers. The full Markdown parse and sanitization
still run, and a growing paragraph may replace its subtree: this is not a fully incremental parser.
Very large sources (over 250,000 UTF-16 code units) fall back to plain text without truncation.

## Security boundary

- Treat model output as untrusted. Markdown raw HTML is disabled. DOMPurify sanitizes generated
  HTML/MathML/SVG before insertion; KaTeX `trust` is false and expansion/size are bounded.
- Only bundled scripts, styles and fonts load. CSP blocks network requests, frames, forms and images.
- Native navigation permits the bundled entry document and opens only user-activated HTTP(S)/mailto
  links externally. No `file:`, custom application scheme or JavaScript links are opened.
- Sanitization preserves inert MathML `semantics`/`annotation`, but not `annotation-xml`.
- Swift passes source through `callAsyncJavaScript` arguments, never JavaScript interpolation.
- An ephemeral website data store and a weak script-message handler avoid persistent browser state
  and retain cycles. Messages must come from this view's main frame and current render revision.

## Rebuilding offline assets

From `WebRenderer/`, with a supported Node version:

```
npm ci --ignore-scripts
npm run build
```

Commit source, lockfile, generated assets and license/manifest changes together. Do not edit the
minified bundle by hand. The builder includes runtime dependency licenses, not build-tool binaries.
Check dependency advisories before upgrades. This does not authorize running any other repository
or package scripts.

## Validation / upstream merge gate

Build the application and run the existing Markdown suite on a compatible Mac, using the repository's
build instructions. Verify tables at narrow widths, inline/block math, incomplete streamed input,
font changes, light/dark mode, toggling raw Markdown, copy/select/link behavior, cancellation/new queries,
multiple service results, renderer failure and window resizing. Check there are no external asset requests.
Parser tests run with `npm run test:unit`; sanitizer/DOM checks use `npm run test:dom`.
The browser regression suite runs with `CHROMIUM_PATH=/path/to/chrome npm test` in `WebRenderer/`.
The native `RichMarkdownViewTests` suite exercises the actual bundled resources through WebKit.
Linux-only resource checks are not sufficient evidence that WebKit/AppKit integration works.
